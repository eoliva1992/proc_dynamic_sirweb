import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../models/procedimiento.dart';
import '_editor_oracle_theme.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import 'procedure_diff_panel.dart';

class CodeEditorPanel extends StatefulWidget {
  final Procedimiento procedimiento;

  const CodeEditorPanel({super.key, required this.procedimiento});

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  bool _ready = false;
  MonacoController? _ctrl;
  Timer? _debounce;

  // Multi-documento: un editor, múltiples modelos con undo stack independiente
  final Map<String, MonacoDocument> _docs = {};
  final List<Procedimiento> _openProcs = [];
  String? _activeProcId;

  // Decoraciones para resaltar líneas con errores (independientes de markers)
  MonacoDecorationSet? _errorDecos;
  MonacoCompletionRegistration? _completionReg;

  bool get _isActiveJs {
    final proc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == _activeProcId,
      orElse: () => widget.procedimiento,
    );
    return proc.inConfiguracion == 'J';
  }

  @override
  void initState() {
    super.initState();
    _openProcs.add(widget.procedimiento);
    _activeProcId = widget.procedimiento.cdProcedimiento;
    // Two frames ensure DWM/DirectComposition is ready before WebView2 init.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _ready = true);
      });
    });
  }

  @override
  void didUpdateWidget(CodeEditorPanel old) {
    super.didUpdateWidget(old);
    if (old.procedimiento.cdProcedimiento !=
        widget.procedimiento.cdProcedimiento) {
      _switchToProc(widget.procedimiento);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _completionReg?.dispose();
    _errorDecos?.dispose();
    super.dispose();
  }

  // ── Setup al estar listo ────────────────────────────────────────────────

  Future<void> _onReady(MonacoController ctrl) async {
    _ctrl = ctrl;

    // Definir tema Oracle en esta instancia Monaco
    await ctrl.defineTheme(oracleDark);
    await ctrl.defineTheme(oracleLight);

    // Abrir el procedimiento actual como documento con URI estable
    final proc = widget.procedimiento;
    final doc = await ctrl.openDocument(
      text: proc.deTexto,
      language: _langFor(proc),
      uri: _uriFor(proc),
    );
    _docs[proc.cdProcedimiento] = doc;
    await ctrl.activateDocument(doc);

    // Completions PL/SQL (activas para SQL y lenguaje custom 'plsql')
    _completionReg = await ctrl.registerStaticCompletions(
      id: 'plsql-keywords',
      languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
      triggerCharacters: [' ', '.', '('],
      items: plsqlCompletionItems,
    );

    // Conjunto de decoraciones para líneas con errores
    _errorDecos = await ctrl.createDecorationSet();

    // LSP: intentar conectar sql-language-server si está instalado
    _tryConnectLsp(ctrl);

    _scheduleCheck(proc.deTexto);
    if (mounted) setState(() {});
  }

  // ── Multi-documento ────────────────────────────────────────────────────

  Future<void> _switchToProc(Procedimiento proc) async {
    final ctrl = _ctrl;
    if (ctrl == null) {
      // Editor aún no listo — actualizar la lista para que _onReady lo tome
      if (mounted) {
        setState(() {
          if (!_openProcs.any(
            (p) => p.cdProcedimiento == proc.cdProcedimiento,
          )) {
            _openProcs.add(proc);
          }
          _activeProcId = proc.cdProcedimiento;
        });
      }
      return;
    }

    if (!_docs.containsKey(proc.cdProcedimiento)) {
      final doc = await ctrl.openDocument(
        text: proc.deTexto,
        language: _langFor(proc),
        uri: _uriFor(proc),
      );
      _docs[proc.cdProcedimiento] = doc;
      if (mounted) {
        setState(() {
          if (!_openProcs.any(
            (p) => p.cdProcedimiento == proc.cdProcedimiento,
          )) {
            _openProcs.add(proc);
          }
        });
      }
    }

    await ctrl.activateDocument(_docs[proc.cdProcedimiento]!);
    if (mounted) setState(() => _activeProcId = proc.cdProcedimiento);
    _scheduleCheck(proc.deTexto);
  }

  Future<void> _closeDoc(Procedimiento proc) async {
    if (_openProcs.length <= 1) return;
    final doc = _docs.remove(proc.cdProcedimiento);
    setState(
      () => _openProcs.removeWhere(
        (p) => p.cdProcedimiento == proc.cdProcedimiento,
      ),
    );
    if (_activeProcId == proc.cdProcedimiento && _openProcs.isNotEmpty) {
      await _switchToProc(_openProcs.last);
    }
    await doc?.close();
  }

  // ── Checkers de sintaxis ───────────────────────────────────────────────

  void _scheduleCheck(String code) {
    if (_isActiveJs) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkPlSql(code),
    );
  }

  Future<void> _checkPlSql(String code) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final issues = checkPlSqlSyntax(code);

    // Markers — squiggles rojos en el texto
    await ctrl.document.setMarkers([
      for (final e in issues)
        MarkerData(
          range: Range(
            startLine: e.line,
            startColumn: e.col,
            endLine: e.line,
            endColumn: e.endCol,
          ),
          message: e.message,
          severity: e.severity,
          source: 'PL/SQL',
        ),
    ], owner: 'plsql-checker');

    // Decoraciones — fondo rojo suave en la línea entera + indicador en minimap/overview
    await _errorDecos?.set([
      for (final e in issues)
        DecorationOptions.line(
          range: Range.lines(e.line, e.line),
          className: 'plsql-error-line',
          additionalOptions: {
            'overviewRuler': {'color': '#FF4444', 'position': 4},
            'minimap': {'color': '#FF4444', 'position': 1},
          },
        ),
    ]);
  }

  // ── LSP ────────────────────────────────────────────────────────────────

  Future<void> _tryConnectLsp(MonacoController ctrl) async {
    try {
      final server = await LspServerProcess.start('sql-language-server', [
        'up',
        '--method',
        'stdio',
      ]);
      await ctrl.connectLanguageServer(
        id: 'sql-lsp',
        transport: server.transport,
        initializationTimeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // sql-language-server no instalado — saltar silenciosamente
    }
  }

  // ── Diff ───────────────────────────────────────────────────────────────

  Future<void> _openDiff() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final activeProc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == _activeProcId,
      orElse: () => widget.procedimiento,
    );
    final current = await ctrl.document.getText();
    if (!mounted) return;
    await showProcedureDiff(
      context,
      title: 'Diff — ${activeProc.cdProcedimiento}',
      original: activeProc.deTexto,
      modified: current,
      language: activeProc.inConfiguracion == 'J' ? 'javascript' : 'sql',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  MonacoLanguage _langFor(Procedimiento proc) => proc.inConfiguracion == 'J'
      ? MonacoLanguage.javascript
      : MonacoLanguage.sql;

  Uri _uriFor(Procedimiento proc) {
    final ext = proc.inConfiguracion == 'J' ? 'js' : 'sql';
    return Uri.parse('file:///procs/${proc.cdProcedimiento}.$ext');
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Sub-tabs de documentos (solo visible con >1 proc abierto)
        if (_openProcs.length > 1) _buildDocTabs(isDark),

        // Toolbar compacta (Diff, Format)
        _buildToolbar(isDark),

        // Editor Monaco
        Expanded(
          child: MonacoEditor(
            initialText: widget.procedimiento.deTexto,
            options: EditorOptions(
              language: _langFor(widget.procedimiento),
              theme: isDark ? oracleDarkTheme : oracleLightTheme,
              fontSize: 14,
              minimap: const MonacoMinimapOptions(enabled: true),
              wordWrap: MonacoWordWrap.off,
              lineNumbers: MonacoLineNumbers.on,
              renderWhitespace: RenderWhitespace.none,
              tabSize: 2,
              bracketPairColorization: true,
              stickyScroll: const MonacoStickyScroll(enabled: true),
            ),
            showStatusBar: true,
            page: const MonacoPageConfig(
              customCss:
                  '.plsql-error-line { background: rgba(255,68,68,0.1) !important; }',
            ),
            contentDebounce: const Duration(milliseconds: 400),
            onReady: _onReady,
            onContentChanged: _scheduleCheck,
            onError: (err, _) => debugPrint('Monaco error: $err'),
          ),
        ),
      ],
    );
  }

  Widget _buildDocTabs(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _openProcs.length,
        itemBuilder: (_, i) {
          final proc = _openProcs[i];
          final active = proc.cdProcedimiento == _activeProcId;
          return _DocTab(
            proc: proc,
            isActive: active,
            onTap: () => _switchToProc(proc),
            onClose: _openProcs.length > 1 ? () => _closeDoc(proc) : null,
          );
        },
      ),
    );
  }

  Widget _buildToolbar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 24,
      color: isDark ? cs.surfaceContainerLow : cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _ToolBtn(
            icon: Icons.compare_arrows,
            tooltip: 'Ver diff vs. versión guardada',
            onPressed: _openDiff,
          ),
          _ToolBtn(
            icon: Icons.format_align_left,
            tooltip: 'Formatear documento (Shift+Alt+F)',
            onPressed: () => _ctrl?.executeAction(MonacoAction.formatDocument),
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────

class _DocTab extends StatelessWidget {
  final Procedimiento proc;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _DocTab({
    required this.proc,
    required this.isActive,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? cs.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              proc.cdProcedimiento,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: Icon(Icons.close, size: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolBtn({required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
