/// Ejecutor SQL/PL-SQL: editor Monaco + panel de salida profesional.
///
/// Detecta automáticamente el tipo de sentencia bajo el cursor (o de la
/// selección) y enruta al servicio correcto: SELECT, DML/DDL, PL/SQL o
/// EXPLAIN PLAN. Se abre como una pestaña más del tab bar principal, igual
/// que el visor de fuente Oracle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sql_executor_state_controller.dart';
import '../services/sql_statement_analyzer.dart';
import '../widgets/monaco_editor_widget.dart';
import '../widgets/plsql_tables.dart' show extractSqlTables;
import '../widgets/slide_up_panel.dart';
import '../widgets/sql_executor/sql_dml_generator_dialog.dart';
import '../widgets/sql_executor/sql_executor_results_panel.dart';
import '../widgets/sql_executor/sql_executor_status_bar.dart';
import '../widgets/sql_executor/sql_executor_toolbar.dart';

export '../widgets/monaco_snippets.dart' show openSnippetsManager;

class SqlExecutorPage extends StatefulWidget {
  const SqlExecutorPage({
    super.key,
    required this.ambiente,
    required this.onAmbienteChanged,
    this.initialSql = '',
  });

  final String ambiente;
  final ValueChanged<String> onAmbienteChanged;

  /// Sólo para pruebas: siembra el editor sin depender del WebView de Monaco.
  final String initialSql;

  @override
  State<SqlExecutorPage> createState() => _SqlExecutorPageState();
}

class _SqlExecutorPageState extends State<SqlExecutorPage>
    with SingleTickerProviderStateMixin {
  final _monacoCtrl = MonacoEditorController();
  late final TabController _resultTabCtrl = TabController(
    length: 4,
    vsync: this,
  );
  late final SqlExecutorStateController _stateCtrl;

  @override
  void initState() {
    super.initState();
    _stateCtrl = SqlExecutorStateController(
      initialAmbiente: widget.ambiente,
      initialSql: widget.initialSql,
    );
    _stateCtrl.onTabChangeRequested = (idx) {
      if (mounted && _resultTabCtrl.index != idx) {
        _resultTabCtrl.index = idx;
      }
    };
  }

  @override
  void didUpdateWidget(SqlExecutorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ambiente != widget.ambiente) {
      _stateCtrl.setAmbiente(widget.ambiente);
    }
  }

  @override
  void dispose() {
    _resultTabCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  void _onGenerateDml(List<int> rowIndexes) {
    final result = _stateCtrl.lastResult;
    if (result == null) return;
    final tables = extractSqlTables(_stateCtrl.text).values.toSet();
    final table = tables.isEmpty ? '' : tables.first;
    showSqlDmlGeneratorDialog(
      context,
      result: result,
      rowIndexes: rowIndexes,
      suggestedTable: table,
      ambiente: _stateCtrl.ambiente,
      onInsert: (sql) => _monacoCtrl.insertTextAtCursor(sql),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _stateCtrl,
      builder: (context, _) {
        final stmt = _stateCtrl.currentStatement();

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _stateCtrl.runCurrentOrSelection,
            const SingleActivator(LogicalKeyboardKey.f5): _stateCtrl.runAll,
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                SqlExecutorToolbar(
                  ambiente: _stateCtrl.ambiente,
                  onAmbienteChanged: (v) {
                    _stateCtrl.setAmbiente(v);
                    widget.onAmbienteChanged(v);
                  },
                  statement: stmt,
                  running: _stateCtrl.running,
                  onExecuteCurrent: _stateCtrl.runCurrentOrSelection,
                  onExecuteAll: _stateCtrl.runAll,
                  onExplainPlan: _stateCtrl.runExplainPlan,
                  onClearOutput: _stateCtrl.clearOutput,
                ),
                _SqlProgressBar(
                  running: _stateCtrl.running,
                  primaryColor: cs.primary,
                ),
                Expanded(
                  child: _SqlEditorWorkspace(
                    monacoCtrl: _monacoCtrl,
                    stateCtrl: _stateCtrl,
                    resultTabCtrl: _resultTabCtrl,
                    isDark: isDark,
                    onGenerateDml: _onGenerateDml,
                  ),
                ),
                SqlExecutorStatusBar(
                  cursorLine: _stateCtrl.cursorLine,
                  cursorCol: _stateCtrl.cursorCol,
                  statementCount: splitStatements(_stateCtrl.text).length,
                  statement: stmt,
                  running: _stateCtrl.running,
                  lastEntry: _stateCtrl.log.isNotEmpty
                      ? _stateCtrl.log.last
                      : null,
                  ambiente: _stateCtrl.ambiente,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Barra de progreso animada que se muestra durante ejecuciones SQL activas.
class _SqlProgressBar extends StatelessWidget {
  const _SqlProgressBar({required this.running, required this.primaryColor});

  final bool running;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: running ? 2.0 : 0.0,
      child: running
          ? LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              minHeight: 2,
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Área central de trabajo: Editor Monaco junto al panel flotante de resultados/salida.
class _SqlEditorWorkspace extends StatelessWidget {
  const _SqlEditorWorkspace({
    required this.monacoCtrl,
    required this.stateCtrl,
    required this.resultTabCtrl,
    required this.isDark,
    required this.onGenerateDml,
  });

  final MonacoEditorController monacoCtrl;
  final SqlExecutorStateController stateCtrl;
  final TabController resultTabCtrl;
  final bool isDark;
  final ValueChanged<List<int>> onGenerateDml;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MonacoEditorWidget(
          controller: monacoCtrl,
          initialCode: stateCtrl.text,
          language: 'plsql',
          darkTheme: isDark,
          ambiente: stateCtrl.ambiente,
          onChanged: (code) => stateCtrl.setText(code),
          onCursorChanged: (line, col) => stateCtrl.setCursor(line, col),
          onExecuteCurrent: stateCtrl.runCurrentOrSelection,
          onExecuteAll: stateCtrl.runAll,
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SlideUpPanel(
            visible: stateCtrl.resultsPanelVisible,
            height: stateCtrl.resultsPanelHeight,
            child: SizedBox(
              height: stateCtrl.resultsPanelHeight,
              child: SqlExecutorResultsPanel(
                tabController: resultTabCtrl,
                visible: stateCtrl.resultsPanelVisible,
                height: stateCtrl.resultsPanelHeight,
                onHeightChanged: stateCtrl.setResultsPanelHeight,
                onToggleVisible: stateCtrl.toggleResultsPanel,
                lastResult: stateCtrl.lastResult,
                log: stateCtrl.log,
                explainNodes: stateCtrl.explainNodes,
                explainText: stateCtrl.lastExplainResult?.text,
                maxRows: stateCtrl.maxRows,
                onMaxRowsChanged: stateCtrl.setMaxRows,
                onGenerateDml: onGenerateDml,
                onReplay: (e) {
                  monacoCtrl.insertTextAtCursor(e.statementPreview);
                },
              ),
            ),
          ),
        ),
        if (!stateCtrl.resultsPanelVisible)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SqlExecutorCollapsedHandle(
              onExpand: () => stateCtrl.setResultsPanelVisible(true),
              lastResult: stateCtrl.lastResult,
            ),
          ),
      ],
    );
  }
}
