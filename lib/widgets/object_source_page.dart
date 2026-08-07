import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;
import '../services/schema_service.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import '_editor_themes.dart';
import 'status_card.dart';

class ObjectSourcePage extends StatefulWidget {
  final String name;
  final String objectType; // PROCEDURE | FUNCTION | PACKAGE | VIEW | TYPE
  final String ambiente;

  const ObjectSourcePage({
    super.key,
    required this.name,
    required this.objectType,
    required this.ambiente,
  });

  @override
  State<ObjectSourcePage> createState() => _ObjectSourcePageState();
}

class _ObjectSourcePageState extends State<ObjectSourcePage>
    with SingleTickerProviderStateMixin {
  TabController? _tabCtrl;
  ({String spec, String? body})? _data;
  Object? _error;

  // single shared controller — multi-doc for packages/types, single-doc for others
  fm.MonacoController? _specCtrl;
  String _specText = '';
  String _bodyText = '';
  int _specErrors = 0;
  int _bodyErrors = 0;
  bool _compiling = false;

  @override
  void initState() {
    super.initState();
    SchemaService.instance
        .getObjectSource(
          widget.name,
          widget.objectType,
          ambiente: widget.ambiente,
        )
        .then((data) {
          if (!mounted) return;
          setState(() {
            _data = data;
            if (data.body != null) {
              _tabCtrl = TabController(length: 2, vsync: this);
            }
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  void _copyCurrentSource() {
    final text = (_tabCtrl?.index == 1 && _bodyText.isNotEmpty)
        ? _bodyText
        : _specText;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fuente copiado al portapapeles'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _compile() async {
    final isBody = _tabCtrl?.index == 1;
    final ctrl = _specCtrl; // shared controller handles both documents
    final text = isBody ? _bodyText : _specText;
    // PACKAGE BODY needs different objectType for USER_ERRORS query
    final objType = (isBody && widget.objectType == 'PACKAGE')
        ? 'PACKAGE BODY'
        : widget.objectType;

    if (text.isEmpty || ctrl == null) return;
    setState(() => _compiling = true);
    try {
      final errors = await SchemaService.instance.compileObject(
        text,
        widget.name,
        objType,
        ambiente: widget.ambiente,
      );
      await ctrl.document.clearMarkers(owner: 'oracle-compile');
      if (errors.isNotEmpty) {
        await ctrl.document.setMarkers([
          for (final e in errors)
            fm.MarkerData(
              range: fm.Range(
                startLine: e.line,
                startColumn: e.position,
                endLine: e.line,
                endColumn: e.position + 1,
              ),
              message: e.text,
              severity: e.attribute == 'ERROR'
                  ? fm.MarkerSeverity.error
                  : fm.MarkerSeverity.warning,
              source: 'Oracle',
            ),
        ], owner: 'oracle-compile');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errors.isEmpty
                  ? '${widget.name} compilado exitosamente ✓'
                  : '${widget.name}: ${errors.length} error(es) de compilación',
            ),
            backgroundColor: errors.isEmpty
                ? Colors.green.shade700
                : Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _compiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasTabs = _tabCtrl != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              _typeLabel(widget.objectType),
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0078D4),
        foregroundColor: Colors.white,
        bottom: hasTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: ColoredBox(
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF5F7FA),
                  child: TabBar(
                    controller: _tabCtrl,
                    tabs: const [
                      Tab(text: 'Especificación'),
                      Tab(text: 'Cuerpo'),
                    ],
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    indicatorColor: const Color(0xFF0078D4),
                    labelColor: const Color(0xFF0078D4),
                    unselectedLabelColor: isDark
                        ? Colors.white54
                        : Colors.black54,
                  ),
                ),
              )
            : null,
        actions: [
          if (_data != null) ...[
            IconButton(
              tooltip: 'Copiar fuente',
              icon: const Icon(Icons.content_copy_outlined, size: 20),
              onPressed: _copyCurrentSource,
            ),
            IconButton(
              tooltip: 'Compilar y guardar',
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              onPressed: _compiling ? null : _compile,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _buildBody(isDark),
          // Loading/compiling overlay — same pattern as MainScreen + SchemaStatusOverlay
          Positioned(
            left: 12,
            bottom: 12,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: (_data == null || _compiling) ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: _data != null && !_compiling,
                child: StatusCard(
                  message: _compiling ? 'Compilando...' : 'Cargando fuente...',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return const SizedBox.expand();
    }

    if (_tabCtrl != null) {
      return Column(
        children: [
          _buildErrorBar(isDark),
          Expanded(
            child: _MultiDocSourceEditor(
              spec: _data!.spec,
              body: _data!.body,
              isDark: isDark,
              ambiente: widget.ambiente,
              isPlSql: widget.objectType != 'VIEW',
              tabCtrl: _tabCtrl!,
              onControllerReady: (c) => setState(() {
                _specCtrl = c;
                _specText = _data!.spec;
                _bodyText = _data!.body ?? '';
              }),
              onSpecTextChanged: (t) => _specText = t,
              onBodyTextChanged: (t) => _bodyText = t,
              onSpecErrorsChanged: (n) => setState(() => _specErrors = n),
              onBodyErrorsChanged: (n) => setState(() => _bodyErrors = n),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildErrorBar(isDark),
        Expanded(
          child: _MonacoSourceTab(
            source: _data!.spec,
            isDark: isDark,
            ambiente: widget.ambiente,
            isPlSql: widget.objectType != 'VIEW',
            onControllerReady: (c) => setState(() {
              _specCtrl = c;
              _specText = _data!.spec;
            }),
            onTextChanged: (t) => _specText = t,
            onErrorCountChanged: (n) => setState(() => _specErrors = n),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBar(bool isDark) {
    final totalErrors = _specErrors + _bodyErrors;
    return Container(
      height: 34,
      color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (totalErrors > 0) ...[
            Icon(Icons.error_outline, size: 13, color: Colors.red.shade400),
            const SizedBox(width: 4),
            Text(
              '$totalErrors error${totalErrors != 1 ? 'es' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.red.shade400),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  static String _typeLabel(String type) => switch (type) {
    'PROCEDURE' => 'Procedimiento',
    'FUNCTION' => 'Función',
    'PACKAGE' => 'Paquete',
    'VIEW' => 'Vista',
    'TYPE' => 'Tipo',
    _ => type,
  };
}

// Keeps the Monaco editor alive when switching tabs so it doesn't reload.
// Handles ANTLR4 injection, schema completions and PL/SQL syntax checking.
class _MonacoSourceTab extends StatefulWidget {
  final String source;
  final bool isDark;
  final String ambiente;
  final bool isPlSql;
  final void Function(fm.MonacoController ctrl)? onControllerReady;
  final void Function(String text)? onTextChanged;
  final void Function(int errorCount)? onErrorCountChanged;

  const _MonacoSourceTab({
    required this.source,
    required this.isDark,
    required this.ambiente,
    required this.isPlSql,
    this.onControllerReady,
    this.onTextChanged,
    this.onErrorCountChanged,
  });

  @override
  State<_MonacoSourceTab> createState() => _MonacoSourceTabState();
}

class _MonacoSourceTabState extends State<_MonacoSourceTab>
    with AutomaticKeepAliveClientMixin {
  fm.MonacoController? _ctrl;
  fm.MonacoCompletionRegistration? _kwReg;
  bool _antlrReady = false;
  bool _contentReady = false; // true once monacoSetValue has been called
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _kwReg?.dispose();
    editorThemeStore.removeListener(_onEditorThemeChanged);
    super.dispose();
  }

  void _onEditorThemeChanged() {
    _ctrl?.setTheme(editorThemeStore.monacoTheme);
  }

  Future<void> _onReady(fm.MonacoController ctrl) async {
    _ctrl = ctrl;
    widget.onControllerReady?.call(ctrl);
    await EditorThemeStore.defineAllThemes(ctrl);
    await ctrl.setTheme(editorThemeStore.monacoTheme);
    editorThemeStore.addListener(_onEditorThemeChanged);

    // Static PL/SQL keyword completions
    _kwReg = await ctrl.registerStaticCompletions(
      id: 'plsql-source-kw',
      languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
      triggerCharacters: const [' ', '.', '('],
      items: plsqlCompletionItems,
    );

    // Send Oracle schema to the HTML completion provider
    _loadSchema(ctrl);

    // ANTLR4 for PL/SQL syntax checking
    if (widget.isPlSql) {
      _injectAntlr(ctrl);
    }

    // Tab accepts suggestions; Enter does not
    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter:"off", tabCompletion:"on"'
      '}); } catch(e) {}',
    );

    // Push source after editor is ready so Monaco renders before tokenizing
    if (widget.source.isNotEmpty) {
      await ctrl.runJavaScript('monacoSetValue(${jsonEncode(widget.source)})');
    }
    if (mounted) setState(() => _contentReady = true);
    if (widget.isPlSql && widget.source.isNotEmpty) {
      _scheduleCheck(widget.source);
    }
  }

  Future<void> _loadSchema(fm.MonacoController ctrl) async {
    try {
      final schema = await SchemaService.instance.getMetadata(
        ambiente: widget.ambiente,
      );
      final payload = jsonEncode({
        'action': 'setCompletionSchema',
        'tables': schema.tables,
        'views': schema.views,
        'objects': schema.objects
            .map((o) => {'name': o.name, 'type': o.type})
            .toList(),
      });
      await ctrl.runJavaScript('monacoReceiveMessage($payload)');
    } catch (_) {}
  }

  Future<void> _injectAntlr(fm.MonacoController ctrl) async {
    try {
      final src = await rootBundle.loadString('assets/plsql_checker.js');
      await ctrl.runJavaScript(src);
      if (mounted) setState(() => _antlrReady = true);
    } catch (_) {}
  }

  void _scheduleCheck(String code) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkSyntax(code),
    );
  }

  Future<void> _checkSyntax(String code) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    List<PlSqlIssue> issues;
    if (_antlrReady) {
      try {
        await ctrl.runJavaScript('window.__plsqlCode=${jsonEncode(code)};');
        final raw = await ctrl.evaluateJavaScript<String>(
          '__checkPlSql(window.__plsqlCode)',
        );
        issues = raw != null ? _parseAntlrResult(raw) : checkPlSqlSyntax(code);
      } catch (_) {
        issues = checkPlSqlSyntax(code);
      }
    } else {
      issues = checkPlSqlSyntax(code);
    }

    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    widget.onErrorCountChanged?.call(errCount);

    await ctrl.document.setMarkers([
      for (final e in issues)
        fm.MarkerData(
          range: fm.Range(
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
  }

  List<PlSqlIssue> _parseAntlrResult(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return [
        for (final e in list)
          PlSqlIssue(
            line: (e['line'] as num).toInt(),
            col: (e['col'] as num).toInt(),
            endCol: (e['col'] as num).toInt() + 1,
            message: e['msg'] as String,
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.source.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        fm.MonacoEditor(
          initialText: '', // content pushed via monacoSetValue in onReady
          options: fm.EditorOptions(
            language: fm.MonacoLanguage.sql,
            theme: widget.isDark ? fm.MonacoTheme.vsDark : fm.MonacoTheme.vs,
            fontSize: 14,
            minimap: const fm.MonacoMinimapOptions(enabled: true),
            lineNumbers: fm.MonacoLineNumbers.on,
            wordWrap: fm.MonacoWordWrap.off,
            renderWhitespace: fm.RenderWhitespace.none,
            tabSize: 2,
          ),
          contentDebounce: const Duration(milliseconds: 300),
          onReady: _onReady,
          onContentChanged: (text) {
            widget.onTextChanged?.call(text);
            if (widget.isPlSql) _scheduleCheck(text);
          },
        ),
        if (!_contentReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando contenido...'),
          ),
      ],
    );
  }
}

// Single Monaco WebView with two documents — spec loads immediately, body after.
// Tab switching activates the corresponding document without recreating the WebView.
class _MultiDocSourceEditor extends StatefulWidget {
  final String spec;
  final String? body;
  final bool isDark;
  final String ambiente;
  final bool isPlSql;
  final TabController tabCtrl;
  final void Function(fm.MonacoController)? onControllerReady;
  final void Function(String)? onSpecTextChanged;
  final void Function(String)? onBodyTextChanged;
  final void Function(int)? onSpecErrorsChanged;
  final void Function(int)? onBodyErrorsChanged;

  const _MultiDocSourceEditor({
    required this.spec,
    required this.body,
    required this.isDark,
    required this.ambiente,
    required this.isPlSql,
    required this.tabCtrl,
    this.onControllerReady,
    this.onSpecTextChanged,
    this.onBodyTextChanged,
    this.onSpecErrorsChanged,
    this.onBodyErrorsChanged,
  });

  @override
  State<_MultiDocSourceEditor> createState() => _MultiDocSourceEditorState();
}

class _MultiDocSourceEditorState extends State<_MultiDocSourceEditor> {
  fm.MonacoController? _ctrl;
  fm.MonacoDocument? _specDoc;
  fm.MonacoDocument? _bodyDoc;
  fm.MonacoCompletionRegistration? _kwReg;
  bool _antlrReady = false;
  bool _specReady = false;
  Timer? _debounce;
  bool _isBody = false;

  @override
  void initState() {
    super.initState();
    widget.tabCtrl.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabCtrl.removeListener(_onTabChanged);
    _debounce?.cancel();
    _kwReg?.dispose();
    editorThemeStore.removeListener(_onEditorThemeChanged2);
    super.dispose();
  }

  void _onEditorThemeChanged2() {
    _ctrl?.setTheme(editorThemeStore.monacoTheme);
  }

  void _onTabChanged() {
    final wantsBody = widget.tabCtrl.index == 1;
    if (_isBody == wantsBody) return;
    _isBody = wantsBody;
    final doc = wantsBody ? _bodyDoc : _specDoc;
    if (doc != null) _ctrl?.activateDocument(doc);
  }

  Future<void> _onReady(fm.MonacoController ctrl) async {
    _ctrl = ctrl;
    widget.onControllerReady?.call(ctrl);
    await EditorThemeStore.defineAllThemes(ctrl);
    await ctrl.setTheme(editorThemeStore.monacoTheme);
    editorThemeStore.addListener(_onEditorThemeChanged2);

    _kwReg = await ctrl.registerStaticCompletions(
      id: 'plsql-multidoc-kw',
      languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
      triggerCharacters: const [' ', '.', '('],
      items: plsqlCompletionItems,
    );

    _loadSchema(ctrl);
    if (widget.isPlSql) _injectAntlr(ctrl);

    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter:"off", tabCompletion:"on"'
      '}); } catch(e) {}',
    );

    // Spec loads first and becomes immediately visible
    _specDoc = await ctrl.openDocument(
      text: widget.spec,
      language: fm.MonacoLanguage.sql,
      uri: Uri.parse('file:///source/spec.sql'),
    );
    await ctrl.activateDocument(_specDoc!);
    widget.onSpecTextChanged?.call(widget.spec);
    if (mounted) setState(() => _specReady = true);
    if (widget.isPlSql && widget.spec.isNotEmpty) {
      _scheduleCheck(widget.spec, isBody: false);
    }

    // Body document opens in background — no visible switch
    if (widget.body != null && widget.body!.isNotEmpty) {
      _bodyDoc = await ctrl.openDocument(
        text: widget.body!,
        language: fm.MonacoLanguage.sql,
        uri: Uri.parse('file:///source/body.sql'),
      );
      widget.onBodyTextChanged?.call(widget.body!);
    }
  }

  Future<void> _loadSchema(fm.MonacoController ctrl) async {
    try {
      final schema = await SchemaService.instance.getMetadata(
        ambiente: widget.ambiente,
      );
      final payload = jsonEncode({
        'action': 'setCompletionSchema',
        'tables': schema.tables,
        'views': schema.views,
        'objects': schema.objects
            .map((o) => {'name': o.name, 'type': o.type})
            .toList(),
      });
      await ctrl.runJavaScript('monacoReceiveMessage($payload)');
    } catch (_) {}
  }

  Future<void> _injectAntlr(fm.MonacoController ctrl) async {
    try {
      final src = await rootBundle.loadString('assets/plsql_checker.js');
      await ctrl.runJavaScript(src);
      if (mounted) setState(() => _antlrReady = true);
    } catch (_) {}
  }

  void _scheduleCheck(String code, {required bool isBody}) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkSyntax(code, isBody: isBody),
    );
  }

  Future<void> _checkSyntax(String code, {required bool isBody}) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    List<PlSqlIssue> issues;
    if (_antlrReady) {
      try {
        await ctrl.runJavaScript('window.__plsqlCode=${jsonEncode(code)};');
        final raw = await ctrl.evaluateJavaScript<String>(
          '__checkPlSql(window.__plsqlCode)',
        );
        issues = raw != null ? _parseAntlrResult(raw) : checkPlSqlSyntax(code);
      } catch (_) {
        issues = checkPlSqlSyntax(code);
      }
    } else {
      issues = checkPlSqlSyntax(code);
    }

    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    if (isBody) {
      widget.onBodyErrorsChanged?.call(errCount);
    } else {
      widget.onSpecErrorsChanged?.call(errCount);
    }

    await ctrl.document.setMarkers([
      for (final e in issues)
        fm.MarkerData(
          range: fm.Range(
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
  }

  List<PlSqlIssue> _parseAntlrResult(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return [
        for (final e in list)
          PlSqlIssue(
            line: (e['line'] as num).toInt(),
            col: (e['col'] as num).toInt(),
            endCol: (e['col'] as num).toInt() + 1,
            message: e['msg'] as String,
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        fm.MonacoEditor(
          initialText: '',
          options: fm.EditorOptions(
            language: fm.MonacoLanguage.sql,
            theme: editorThemeStore.monacoTheme,
            fontSize: 14,
            minimap: const fm.MonacoMinimapOptions(enabled: true),
            lineNumbers: fm.MonacoLineNumbers.on,
            wordWrap: fm.MonacoWordWrap.off,
            renderWhitespace: fm.RenderWhitespace.none,
            tabSize: 2,
          ),
          contentDebounce: const Duration(milliseconds: 300),
          onReady: _onReady,
          onContentChanged: (text) {
            if (_isBody) {
              widget.onBodyTextChanged?.call(text);
              if (widget.isPlSql) _scheduleCheck(text, isBody: true);
            } else {
              widget.onSpecTextChanged?.call(text);
              if (widget.isPlSql) _scheduleCheck(text, isBody: false);
            }
          },
        ),
        if (!_specReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando especificación...'),
          ),
      ],
    );
  }
}
