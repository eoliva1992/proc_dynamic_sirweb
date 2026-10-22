/// Ejecutor SQL/PL-SQL: editor Monaco + panel de salida profesional.
///
/// Detecta automáticamente el tipo de sentencia bajo el cursor (o de la
/// selección) y enruta al servicio correcto: SELECT, DML/DDL, PL/SQL o
/// EXPLAIN PLAN. Se abre como una pestaña más del tab bar principal, igual
/// que el visor de fuente Oracle.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sql_execution.dart' show SqlStatement, SqlDdlError;
import '../providers/procedimientos_provider.dart';
import '../services/backup_service.dart';
import '../services/local_file_service.dart';
import '../services/sql_executor_state_controller.dart';
import '../widgets/constellation_background.dart' show ConstellationDialogTitle;
import '../widgets/editor_split_container.dart';
import '../widgets/monaco_editor_widget.dart';
import '../widgets/plsql_tables.dart' show extractSqlTables;
import '../widgets/slide_up_panel.dart';
import '../widgets/sql_executor/sql_dml_generator_dialog.dart';
import '../widgets/sql_executor/sql_executor_results_panel.dart';
import '../widgets/sql_executor/sql_executor_status_bar.dart';
import '../widgets/sql_executor/sql_executor_toolbar.dart';
import '../widgets/usuario_dialog.dart';

export '../widgets/monaco_snippets.dart' show openSnippetsManager;

class SqlExecutorPage extends StatefulWidget {
  const SqlExecutorPage({
    super.key,
    required this.ambiente,
    required this.onAmbienteChanged,
    this.initialSql = '',
    this.initialFilePath,
    this.onCodeChanged,
    this.onFilePathChanged,
  });

  final String ambiente;
  final ValueChanged<String> onAmbienteChanged;

  /// Siembra el editor con código SQL o contenido inicial.
  final String initialSql;

  /// Ruta del archivo local en disco si la pestaña proviene de un archivo .sql abierto.
  final String? initialFilePath;

  /// Notifica cambios en el contenido del editor SQL para sincronización y persistencia.
  final ValueChanged<String>? onCodeChanged;

  /// Notifica cambios en la ruta del archivo local cuando se abre o guarda con nueva ruta.
  final ValueChanged<String?>? onFilePathChanged;

  @override
  State<SqlExecutorPage> createState() => _SqlExecutorPageState();
}

class _SqlExecutorPageState extends State<SqlExecutorPage>
    with SingleTickerProviderStateMixin {
  final _monacoCtrl = MonacoEditorController();
  late final TabController _resultTabCtrl = TabController(
    length: 5,
    vsync: this,
  );
  late final SqlExecutorStateController _stateCtrl;

  @override
  void initState() {
    super.initState();
    _stateCtrl = SqlExecutorStateController(
      initialAmbiente: widget.ambiente,
      initialSql: widget.initialSql,
      initialFilePath: widget.initialFilePath,
    );
    _stateCtrl.getSelectedText = _monacoCtrl.getSelectedText;
    _stateCtrl.ensureUsuario = () async {
      await showUsuarioDialog(context);
      return procedimientosProvider.cdUsuario.trim().isNotEmpty;
    };
    _stateCtrl.confirmProdExecution = _confirmProdExecution;
    _stateCtrl.onDdlCompilationErrors = _handleDdlCompilationErrors;
    _stateCtrl.onTabChangeRequested = (idx) {
      if (mounted && _resultTabCtrl.index != idx) {
        _resultTabCtrl.index = idx;
      }
    };
  }

  void _handleDdlCompilationErrors(
    SqlStatement stmt,
    List<SqlDdlError> errors,
  ) {
    if (errors.isEmpty) {
      _monacoCtrl.clearErrors(owner: 'oracle-compile');
      return;
    }
    // Mapea la posición de los errores relativa a la sentencia
    // Oracle reporta líneas 1-based relativas al inicio del DDL.
    final baseLine = stmt.startLine; // 0-based
    final monacoErrors = <MonacoError>[];
    for (final err in errors) {
      final lineOffset = (err.line != null && err.line! > 0)
          ? (err.line! - 1)
          : 0;
      final targetLine = baseLine + lineOffset + 1; // 1-based para Monaco
      final targetCol = (err.position != null && err.position! > 0)
          ? err.position!
          : 1;
      monacoErrors.add(
        MonacoError(
          line: targetLine,
          col: targetCol,
          message: err.text ?? 'Error de compilación en Oracle',
        ),
      );
    }
    _monacoCtrl.setErrors(monacoErrors, owner: 'oracle-compile');
  }

  Future<bool> _confirmProdExecution(SqlStatement stmt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: const ConstellationDialogTitle(
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Ejecutar en Producción'),
            ],
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Estás por ejecutar una sentencia ${stmt.kind.name.toUpperCase()} '
            'en el ambiente de Producción. Esto puede modificar datos reales.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ejecutar'),
          ),
        ],
      ),
    );
    return confirmed == true;
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

    // Priorizamos la sentencia que dio origen al resultado activo
    final selectedIdx = _stateCtrl.selectedResultIndex;
    final results = _stateCtrl.results;
    final sourceSql = (selectedIdx >= 0 && selectedIdx < results.length)
        ? results[selectedIdx].statementText
        : '';

    var tables = sourceSql.trim().isNotEmpty
        ? extractSqlTables(sourceSql).values.toSet()
        : <String>{};

    // Fallback: si no se detectó tabla en sourceSql, intentar con el texto completo
    if (tables.isEmpty) {
      tables = extractSqlTables(_stateCtrl.text).values.toSet();
    }

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

  Future<void> _openLocalSqlFile() async {
    final opened = await LocalFileService.openFile(
      dialogTitle: 'Abrir script SQL',
      allowedExtensions: const ['sql', 'txt', 'pls'],
    );
    if (opened == null || !mounted) return;
    _stateCtrl.loadFromLocalFile(path: opened.path, content: opened.content);
    widget.onFilePathChanged?.call(opened.path);
    _monacoCtrl.setText(opened.content);
  }

  Future<void> _saveLocalSqlFile({bool saveAs = false}) async {
    final code = _stateCtrl.text;
    final savedPath = await LocalFileService.saveFile(
      content: code,
      currentPath: _stateCtrl.currentFilePath,
      saveAs: saveAs,
      defaultFileName: 'script.sql',
      dialogTitle: saveAs ? 'Guardar script como…' : 'Guardar script',
      allowedExtensions: const ['sql', 'txt', 'pls'],
    );
    if (savedPath != null && mounted) {
      _stateCtrl.setCurrentFilePath(savedPath);
      widget.onFilePathChanged?.call(savedPath);
    }
  }

  Future<void> _newSqlScript() async {
    final hasContent = _stateCtrl.text.trim().isNotEmpty;
    final hasChanges = _stateCtrl.hasPendingChanges || hasContent;

    if (hasChanges) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nuevo script'),
          content: const Text(
            'El script actual tiene contenido o cambios pendientes. '
            '¿Desea limpiar el editor y comenzar un nuevo documento?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Limpiar editor'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    _monacoCtrl.setText('');
    _stateCtrl.setText('');
    _stateCtrl.setCurrentFilePath(null);
    widget.onFilePathChanged?.call(null);
    _stateCtrl.clearOutput();
  }

  Future<void> _confirmClearOutput() async {
    final hasResults = _stateCtrl.results.isNotEmpty;
    final hasLog = _stateCtrl.log.isNotEmpty;
    if (!hasResults && !hasLog && _stateCtrl.explainNodes == null) {
      _stateCtrl.clearOutput();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar salida'),
        content: const Text(
          '¿Deseas limpiar todos los resultados, mensajes y el plan de ejecución?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _stateCtrl.clearOutput();
    }
  }

  // Cachea el workspace (panel de resultados + Monaco) para que no se
  // reconstruya en cada tecla/movimiento de cursor, sólo cuando cambia algo
  // que realmente afecta (resultados, panel, tema).
  int? _workspaceRevision;
  bool? _workspaceIsDark;
  Widget? _workspaceCache;

  Widget _buildWorkspace(bool isDark) {
    final cached = _workspaceCache;
    if (cached != null &&
        _workspaceRevision == _stateCtrl.revision &&
        _workspaceIsDark == isDark) {
      return cached;
    }
    _workspaceRevision = _stateCtrl.revision;
    _workspaceIsDark = isDark;
    return _workspaceCache = _SqlEditorWorkspace(
      monacoCtrl: _monacoCtrl,
      stateCtrl: _stateCtrl,
      resultTabCtrl: _resultTabCtrl,
      isDark: isDark,
      onGenerateDml: _onGenerateDml,
      onSave: () => unawaited(_saveLocalSqlFile()),
      onSaveAs: () => unawaited(_saveLocalSqlFile(saveAs: true)),
      onCodeChanged: widget.onCodeChanged,
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
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_stateCtrl.running) _stateCtrl.cancel();
            },
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
                unawaited(_newSqlScript()),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                unawaited(_saveLocalSqlFile()),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              control: true,
              shift: true,
            ): () =>
                unawaited(_saveLocalSqlFile(saveAs: true)),
            const SingleActivator(
              LogicalKeyboardKey.backslash,
              control: true,
            ): () {
              if (_stateCtrl.splitMode == EditorSplitMode.none) {
                _stateCtrl.setSplitMode(EditorSplitMode.vertical);
              } else {
                _stateCtrl.closeSplit();
              }
            },
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
                  onCancel: _stateCtrl.cancel,
                  onClearOutput: () => unawaited(_confirmClearOutput()),
                  onNewFile: () => unawaited(_newSqlScript()),
                  onOpenFile: () => unawaited(_openLocalSqlFile()),
                  onSaveFile: () => unawaited(_saveLocalSqlFile()),
                  onSaveFileAs: () =>
                      unawaited(_saveLocalSqlFile(saveAs: true)),
                  onRevealInExplorer: _stateCtrl.currentFilePath != null
                      ? () => unawaited(
                          BackupService.revealInExplorer(
                            _stateCtrl.currentFilePath!,
                          ),
                        )
                      : null,
                  currentFilePath: _stateCtrl.currentFilePath,
                  hasPendingChanges: _stateCtrl.hasPendingChanges,
                  onCommit: _stateCtrl.commit,
                  onRollback: _stateCtrl.rollback,
                  runStartedAt: _stateCtrl.runStartedAt,
                  hasUnexecutedChanges: _stateCtrl.hasUnexecutedChanges,
                  timeoutSeconds: _stateCtrl.timeoutSeconds,
                  onTimeoutChanged: _stateCtrl.setTimeoutSeconds,
                  maxRows: _stateCtrl.maxRows,
                  onMaxRowsChanged: _stateCtrl.setMaxRows,
                  splitMode: _stateCtrl.splitMode,
                  onSplitModeChanged: _stateCtrl.setSplitMode,
                ),
                _SqlProgressBar(
                  running: _stateCtrl.running,
                  primaryColor: cs.primary,
                ),
                Expanded(child: _buildWorkspace(isDark)),
                SqlExecutorStatusBar(
                  cursorLine: _stateCtrl.cursorLine,
                  cursorCol: _stateCtrl.cursorCol,
                  statementCount: _stateCtrl.statements.length,
                  statement: stmt,
                  running: _stateCtrl.running,
                  lastEntry: _stateCtrl.log.isNotEmpty
                      ? _stateCtrl.log.last
                      : null,
                  ambiente: _stateCtrl.ambiente,
                  currentFilePath: _stateCtrl.currentFilePath,
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
class _SqlEditorWorkspace extends StatefulWidget {
  const _SqlEditorWorkspace({
    required this.monacoCtrl,
    required this.stateCtrl,
    required this.resultTabCtrl,
    required this.isDark,
    required this.onGenerateDml,
    this.onSave,
    this.onSaveAs,
    this.onCodeChanged,
  });

  final MonacoEditorController monacoCtrl;
  final SqlExecutorStateController stateCtrl;
  final TabController resultTabCtrl;
  final bool isDark;
  final ValueChanged<List<int>> onGenerateDml;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final ValueChanged<String>? onCodeChanged;

  @override
  State<_SqlEditorWorkspace> createState() => _SqlEditorWorkspaceState();
}

class _SqlEditorWorkspaceState extends State<_SqlEditorWorkspace> {
  Offset? _detachedPosition;
  double _detachedWidth = 720;
  double _detachedHeight = 380;
  final MonacoEditorController _monacoCtrl2 = MonacoEditorController();
  bool _isSyncing = false;

  @override
  void dispose() {
    _monacoCtrl2.dispose();
    super.dispose();
  }

  void _onWindowDrag(Offset delta, Size workspaceSize) {
    setState(() {
      final current =
          _detachedPosition ??
          Offset(
            (workspaceSize.width - _detachedWidth).clamp(
                  20.0,
                  double.infinity,
                ) /
                2,
            (workspaceSize.height - _detachedHeight).clamp(
                  20.0,
                  double.infinity,
                ) /
                2,
          );
      final maxX = (workspaceSize.width - 120).clamp(0.0, double.infinity);
      final maxY = (workspaceSize.height - 60).clamp(0.0, double.infinity);
      _detachedPosition = Offset(
        (current.dx + delta.dx).clamp(0.0, maxX),
        (current.dy + delta.dy).clamp(0.0, maxY),
      );
    });
  }

  void _onResizeDrag(DragUpdateDetails details) {
    setState(() {
      _detachedWidth = (_detachedWidth + details.delta.dx).clamp(360.0, 1600.0);
      _detachedHeight = (_detachedHeight + details.delta.dy).clamp(
        180.0,
        900.0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final stateCtrl = widget.stateCtrl;
    final isDark = widget.isDark;
    final monacoCtrl = widget.monacoCtrl;
    final resultTabCtrl = widget.resultTabCtrl;
    final onGenerateDml = widget.onGenerateDml;
    final onSave = widget.onSave;
    final onSaveAs = widget.onSaveAs;

    return LayoutBuilder(
      builder: (context, constraints) {
        final workspaceSize = constraints.biggest;
        final isDetached = stateCtrl.resultsPanelDetached;
        final isPinned = stateCtrl.resultsPanelPinned;
        final isVisible = stateCtrl.resultsPanelVisible;

        final pos =
            _detachedPosition ??
            Offset(
              ((workspaceSize.width - _detachedWidth) / 2).clamp(
                12.0,
                double.infinity,
              ),
              ((workspaceSize.height - _detachedHeight) / 2).clamp(
                12.0,
                double.infinity,
              ),
            );

        return Stack(
          fit: StackFit.expand,
          children: [
            EditorSplitContainer(
              splitMode: stateCtrl.splitMode,
              ratio: stateCtrl.splitRatio,
              onRatioChanged: stateCtrl.setSplitRatio,
              onCloseSecondary: stateCtrl.closeSplit,
              primaryChild: MonacoEditorWidget(
                controller: monacoCtrl,
                initialCode: stateCtrl.text,
                language: 'plsql',
                darkTheme: isDark,
                ambiente: stateCtrl.ambiente,
                onChanged: (code) {
                  stateCtrl.setText(code);
                  widget.onCodeChanged?.call(code);
                  if (stateCtrl.splitMode != EditorSplitMode.none &&
                      !_isSyncing) {
                    _isSyncing = true;
                    _monacoCtrl2.setText(code);
                    _isSyncing = false;
                  }
                },
                onCursorChanged: (line, col) => stateCtrl.setCursor(line, col),
                onExecuteCurrent: stateCtrl.runCurrentOrSelection,
                onExecuteAll: stateCtrl.runAll,
                onSave: onSave,
                onSaveAs: onSaveAs,
              ),
              secondaryBuilder: (context) => MonacoEditorWidget(
                controller: _monacoCtrl2,
                initialCode: stateCtrl.text,
                language: 'plsql',
                darkTheme: isDark,
                ambiente: stateCtrl.ambiente,
                onChanged: (code) {
                  stateCtrl.setText(code);
                  widget.onCodeChanged?.call(code);
                  if (!_isSyncing) {
                    _isSyncing = true;
                    monacoCtrl.setText(code);
                    _isSyncing = false;
                  }
                },
                onCursorChanged: (line, col) => stateCtrl.setCursor(line, col),
                onExecuteCurrent: stateCtrl.runCurrentOrSelection,
                onExecuteAll: stateCtrl.runAll,
                onSave: onSave,
                onSaveAs: onSaveAs,
              ),
            ),
            // Modo acoplado (anclado al borde inferior)
            if (!isDetached) ...[
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SlideUpPanel(
                  visible: isVisible,
                  height: stateCtrl.resultsPanelHeight,
                  child: SizedBox(
                    height: stateCtrl.resultsPanelHeight,
                    child: TapRegion(
                      groupId: 'sql_results_panel',
                      onTapOutside: (_) {
                        if (!isPinned && isVisible) {
                          stateCtrl.setResultsPanelVisible(false);
                        }
                      },
                      child: SqlExecutorResultsPanel(
                        tabController: resultTabCtrl,
                        visible: isVisible,
                        height: stateCtrl.resultsPanelHeight,
                        onHeightChanged: stateCtrl.setResultsPanelHeight,
                        onToggleVisible: stateCtrl.toggleResultsPanel,
                        results: stateCtrl.results,
                        selectedResultIndex: stateCtrl.selectedResultIndex,
                        onSelectResult: stateCtrl.selectResult,
                        log: stateCtrl.log,
                        httpTraces: stateCtrl.httpTraces,
                        explainNodes: stateCtrl.explainNodes,
                        explainText: stateCtrl.lastExplainResult?.text,
                        maxRows: stateCtrl.maxRows,
                        onMaxRowsChanged: stateCtrl.setMaxRows,
                        onGenerateDml: onGenerateDml,
                        onReplay: (e) {
                          monacoCtrl.insertTextAtCursor(e.statementPreview);
                        },
                        onClearLog: stateCtrl.clearLog,
                        onClearHttpTraces: stateCtrl.clearHttpTraces,
                        isDetached: false,
                        onToggleDetached: stateCtrl.toggleResultsPanelDetached,
                        isPinned: isPinned,
                        onTogglePinned: stateCtrl.toggleResultsPanelPinned,
                        onLoadMore: () => stateCtrl.loadMoreRows(),
                        isLoadingMore: stateCtrl.loadingMore,
                      ),
                    ),
                  ),
                ),
              ),
              if (!isVisible)
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
            // Modo desacoplado (ventana flotante libre dentro del workspace)
            if (isDetached && isVisible)
              Positioned(
                left: pos.dx,
                top: pos.dy,
                width: _detachedWidth.clamp(320.0, workspaceSize.width),
                height: _detachedHeight.clamp(160.0, workspaceSize.height),
                child: TapRegion(
                  groupId: 'sql_results_panel',
                  onTapOutside: (_) {
                    if (!isPinned && isVisible) {
                      stateCtrl.setResultsPanelVisible(false);
                    }
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SqlExecutorResultsPanel(
                          tabController: resultTabCtrl,
                          visible: true,
                          height: _detachedHeight,
                          onHeightChanged: (h) =>
                              setState(() => _detachedHeight = h),
                          onToggleVisible: () =>
                              stateCtrl.setResultsPanelVisible(false),
                          results: stateCtrl.results,
                          selectedResultIndex: stateCtrl.selectedResultIndex,
                          onSelectResult: stateCtrl.selectResult,
                          log: stateCtrl.log,
                          httpTraces: stateCtrl.httpTraces,
                          explainNodes: stateCtrl.explainNodes,
                          explainText: stateCtrl.lastExplainResult?.text,
                          maxRows: stateCtrl.maxRows,
                          onMaxRowsChanged: stateCtrl.setMaxRows,
                          onGenerateDml: onGenerateDml,
                          onReplay: (e) {
                            monacoCtrl.insertTextAtCursor(e.statementPreview);
                          },
                          onClearLog: stateCtrl.clearLog,
                          onClearHttpTraces: stateCtrl.clearHttpTraces,
                          isDetached: true,
                          onToggleDetached:
                              stateCtrl.toggleResultsPanelDetached,
                          isPinned: isPinned,
                          onTogglePinned: stateCtrl.toggleResultsPanelPinned,
                          onLoadMore: () => stateCtrl.loadMoreRows(),
                          isLoadingMore: stateCtrl.loadingMore,
                          onHeaderDrag: (delta) =>
                              _onWindowDrag(delta, workspaceSize),
                        ),
                      ),
                      // Tirador para redimensionar en esquina inferior derecha
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: _onResizeDrag,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeDownRight,
                            child: Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.bottomRight,
                              padding: const EdgeInsets.all(3),
                              child: Icon(
                                Icons.filter_list_rounded,
                                size: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isDetached && !isVisible)
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
      },
    );
  }
}
