import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:mobx/mobx.dart' show reaction, ReactionDisposer;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/procedimiento.dart';
import '../models/variable_dinamica.dart';
import '../providers/procedimientos_provider.dart';
import '../services/schema_service.dart';
import '_editor_oracle_theme.dart';
import '_editor_themes.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import 'procedure_diff_panel.dart';
import '../services/editor_draft_service.dart';

enum _SaveStatus { idle, saving, saved, error }

class CodeEditorPanel extends StatefulWidget {
  final Procedimiento procedimiento;
  final String ambiente;
  final ValueChanged<bool>? onDirtyChanged;
  final Future<void> Function(String code)? onSave;
  final ValueChanged<String>? onCodeChanged;

  const CodeEditorPanel({
    super.key,
    required this.procedimiento,
    required this.ambiente,
    this.onDirtyChanged,
    this.onSave,
    this.onCodeChanged,
  });

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
  MonacoCompletionRegistration? _variablesReg;
  MonacoCompletionRegistration? _schemaReg; // tablas, columnas, objetos Oracle
  String _editorFullText = ''; // texto completo actual del editor
  ReactionDisposer? _variablesReaction;

  // ── Opciones del editor (persisten en SharedPreferences) ──────────────
  bool _minimap = true;
  bool _lineNumbers = true;
  bool _folding = true;
  bool _readOnly = false;
  double _fontSize = 14.0;
  bool _wordWrap = false;
  bool _renderWhitespace = false;
  bool _bracketPairColorization = true;
  bool _stickyScroll = true;
  bool _smoothScrolling = false;
  bool _mouseWheelZoom = false;
  bool _formatOnPaste = false;
  bool _quickSuggestions = true;
  bool _parameterHints = true;
  bool _hover = true;
  bool _links = true;
  bool _occurrencesHighlight = true;
  bool _contextMenu = true;

  // ── Estado de sesión (no persiste entre reinicios) ─────────────────
  bool _antlrReady = false;
  final Set<String> _modifiedProcs = {};
  final Map<String, int> _errorCounts = {};
  final Map<String, List<PlSqlIssue>> _issuesPerProc = {};
  MonacoActionRegistration? _zoomInAction;
  MonacoActionRegistration? _zoomOutAction;
  MonacoActionRegistration? _saveAction;
  Timer? _saveTimer;
  Timer? _draftDebounce;
  _SaveStatus _saveStatus = _SaveStatus.idle;
  final Map<String, bool> _draftVisible = {}; // procId → show restore banner
  final GlobalKey _varsButtonKey = GlobalKey();

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
    _loadPrefs();
    editorThemeStore.addListener(_onEditorThemeChanged);
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
    editorThemeStore.removeListener(_onEditorThemeChanged);
    _completionReg?.dispose();
    _variablesReg?.dispose();
    _schemaReg?.dispose();
    _variablesReaction?.call();
    _errorDecos?.dispose();
    _zoomInAction?.dispose();
    _zoomOutAction?.dispose();
    _saveAction?.dispose();
    _saveTimer?.cancel();
    _draftDebounce?.cancel();
    super.dispose();
  }

  // ── Setup al estar listo ────────────────────────────────────────────────

  Future<void> _onReady(MonacoController ctrl) async {
    _ctrl = ctrl;

    // Registrar todos los temas custom; built-ins (vs, vs-dark, hc-*) ya existen en Monaco
    await EditorThemeStore.defineAllThemes(ctrl);
    await ctrl.setTheme(editorThemeStore.monacoTheme);

    // Abrir el procedimiento actual como documento con URI estable
    final proc = widget.procedimiento;
    final draft = await EditorDraftService.load(
      proc.cdProcedimiento,
      widget.ambiente,
    );
    final hasDraft = draft != null && draft != proc.deTexto;
    final doc = await ctrl.openDocument(
      text: hasDraft ? draft : proc.deTexto,
      language: _langFor(proc),
      uri: _uriFor(proc),
    );
    _docs[proc.cdProcedimiento] = doc;
    await ctrl.activateDocument(doc);
    // Report initial text so currentEditorCode is set before first keystroke
    widget.onCodeChanged?.call(hasDraft ? draft : proc.deTexto);
    if (hasDraft && mounted) {
      setState(() {
        _modifiedProcs.add(proc.cdProcedimiento);
        _draftVisible[proc.cdProcedimiento] = true;
      });
      widget.onDirtyChanged?.call(true);
    }

    // Completions PL/SQL (activas para SQL y lenguaje custom 'plsql')
    _completionReg = await ctrl.registerStaticCompletions(
      id: 'plsql-keywords',
      languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
      triggerCharacters: [' ', '.', '('],
      items: plsqlCompletionItems,
    );

    await _registerVariableCompletions();
    _variablesReaction = reaction(
      (_) => procedimientosProvider.variablesDinamicas.toList(),
      (_) {
        if (_ctrl != null) _registerVariableCompletions();
      },
    );

    // Completion dinámico: tablas, columnas y objetos Oracle
    _registerSchemaCompletions(ctrl);

    // Tab acepta sugerencias, Enter NO (solo nueva línea)
    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter: "off",'
      '  tabCompletion: "on"'
      '}); } catch(e) {}',
    );

    // Conjunto de decoraciones para líneas con errores
    _errorDecos = await ctrl.createDecorationSet();

    // LSP: intentar conectar sql-language-server si está instalado
    _tryConnectLsp(ctrl);

    _applyEditorOptions();
    _scheduleCheck(proc.deTexto);

    _zoomInAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.zoom.increase'),
        label: 'Aumentar tamaño de fuente',
        keybindings: [MonacoKeybinding(ctrlCmd: true, key: MonacoKey.equal)],
      ),
      () async {
        if (mounted) _toggle(() => _fontSize = (_fontSize + 2).clamp(10, 28));
      },
    );
    _zoomOutAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.zoom.decrease'),
        label: 'Reducir tamaño de fuente',
        keybindings: [MonacoKeybinding(ctrlCmd: true, key: MonacoKey.minus)],
      ),
      () async {
        if (mounted) _toggle(() => _fontSize = (_fontSize - 2).clamp(10, 28));
      },
    );

    _saveAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.save'),
        label: 'Guardar procedimiento',
        keybindings: [MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyS)],
      ),
      () async {
        unawaited(_saveCurrentDocument());
      },
    );

    if (mounted) setState(() {});

    // Inyectar el bundle ANTLR4 en V8/Chromium (no en QuickJS) para detección real de sintaxis
    _injectAntlrBundle(ctrl);
  }

  Future<void> _injectAntlrBundle(MonacoController ctrl) async {
    try {
      final src = await rootBundle.loadString('assets/plsql_checker.js');
      await ctrl.runJavaScript(src);
      if (mounted) setState(() => _antlrReady = true);
    } catch (_) {
      // Bundle no disponible — el checker manual sigue activo
    }
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
      final draft = await EditorDraftService.load(
        proc.cdProcedimiento,
        widget.ambiente,
      );
      final hasDraft = draft != null && draft != proc.deTexto;
      final doc = await ctrl.openDocument(
        text: hasDraft ? draft : proc.deTexto,
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
          if (hasDraft) {
            _modifiedProcs.add(proc.cdProcedimiento);
            _draftVisible[proc.cdProcedimiento] = true;
          }
        });
        if (hasDraft) widget.onDirtyChanged?.call(true);
      }
    }

    await ctrl.activateDocument(_docs[proc.cdProcedimiento]!);
    // Report active document text so currentEditorCode reflects the switched-to proc
    if (mounted) {
      final text = await ctrl.document.getText();
      widget.onCodeChanged?.call(text);
    }
    if (mounted) setState(() => _activeProcId = proc.cdProcedimiento);
    // inConfiguracion puede diferir del procedimiento anterior — actualizar completions
    _registerVariableCompletions();
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

  List<PlSqlIssue> _parseAntlrResult(String json) {
    try {
      final list = jsonDecode(json) as List<dynamic>;
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

    // ANTLR4 corre en el WebView2 (V8); fallback al checker manual mientras carga
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

    if (mounted) {
      setState(() {
        final id = _activeProcId ?? '';
        _errorCounts[id] = issues
            .where((e) => e.severity == MarkerSeverity.error)
            .length;
        _issuesPerProc[id] = issues;
      });
    }

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

  // ── Variables dinámicas ────────────────────────────────────────────────

  List<VariableDinamica> _filteredVariables() {
    final activeConfig = _openProcs
        .cast<Procedimiento?>()
        .firstWhere(
          (p) => p?.cdProcedimiento == _activeProcId,
          orElse: () => null,
        )
        ?.inConfiguracion;
    if (activeConfig == null) return [];
    return procedimientosProvider.variablesDinamicas
        .where((v) => v.inConfiguracion == activeConfig)
        .toList();
  }

  Future<void> _registerSchemaCompletions(MonacoController ctrl) async {
    _schemaReg?.dispose();
    _schemaReg = null;

    // Usa getMetadata() — no dispara refresco, solo lee el caché disponible
    SchemaService.instance
        .getMetadata()
        .then((schema) async {
          if (!mounted) return;
          final ctrl = _ctrl;
          if (ctrl == null) return;

          _schemaReg = await ctrl.registerCompletions(
            id: 'oracle-schema',
            languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
            triggerCharacters: ['.', ' '],
            provider: (request) async {
              final line = request.lineText ?? '';
              final trigger = request.triggerCharacter;
              // Texto completo hasta la línea del cursor para detectar FROM en cualquier línea
              final fullText = _editorFullText;

              // ── Caso 1: "ALIAS." o "TABLA." → columnas de esa tabla ──────────
              if (trigger == '.' || line.endsWith('.')) {
                final dotMatch = RegExp(r'(\w+)\.$').firstMatch(line);
                if (dotMatch != null) {
                  final tableRef = dotMatch.group(1)!.toUpperCase();
                  // Resolver alias en el texto completo del documento
                  final fromMap = _extractFromTables(fullText);
                  final realTable = fromMap[tableRef] ?? tableRef;

                  final cols = await SchemaService.instance.getColumns(
                    realTable,
                  );
                  return CompletionList(
                    suggestions: cols
                        .map(
                          (c) => CompletionItem(
                            label: c.name,
                            kind: CompletionItemKind.field,
                            detail: '${c.dataType} · $realTable',
                            insertText: c.name,
                            sortText: '0${c.name}',
                          ),
                        )
                        .toList(),
                  );
                }
              }

              // ── Caso 2: palabra suelta → prioriza columnas del FROM ───────────
              final word = _wordBefore(line);
              final upper = word.toUpperCase();

              final suggestions = <CompletionItem>[];

              // Extraer tablas del FROM en el texto completo
              final fromMap = _extractFromTables(fullText);
              for (final realTable in fromMap.values.toSet()) {
                // Cargar columnas bajo demanda si no están en caché
                final cols = schema.cachedColumns.containsKey(realTable)
                    ? schema.cachedColumns[realTable]!
                    : await SchemaService.instance.getColumns(realTable);

                suggestions.addAll(
                  cols
                      .where((c) => upper.isEmpty || c.name.startsWith(upper))
                      .map(
                        (c) => CompletionItem(
                          label: c.name,
                          kind: CompletionItemKind.field,
                          detail: '${c.dataType} · $realTable',
                          sortText: '1${c.name}',
                        ),
                      ),
                );
              }

              // Tablas
              suggestions.addAll(
                schema.tables
                    .where((t) => upper.isEmpty || t.startsWith(upper))
                    .map(
                      (t) => CompletionItem(
                        label: t,
                        kind: CompletionItemKind.classType,
                        detail: 'TABLE',
                        sortText: '2$t',
                      ),
                    ),
              );

              // Vistas
              suggestions.addAll(
                schema.views
                    .where((v) => upper.isEmpty || v.startsWith(upper))
                    .map(
                      (v) => CompletionItem(
                        label: v,
                        kind: CompletionItemKind.interfaceType,
                        detail: 'VIEW',
                        sortText: '3$v',
                      ),
                    ),
              );

              // Objetos (procs, funcs, packages)
              suggestions.addAll(
                schema.objects
                    .where((o) => upper.isEmpty || o.name.startsWith(upper))
                    .map(
                      (o) => CompletionItem(
                        label: o.name,
                        kind: o.type == 'FUNCTION'
                            ? CompletionItemKind.functionType
                            : o.type == 'PACKAGE'
                            ? CompletionItemKind.module
                            : CompletionItemKind.method,
                        detail: o.type,
                        sortText: '4${o.name}',
                      ),
                    ),
              );

              return CompletionList(suggestions: suggestions.take(50).toList());
            },
          );
        })
        .catchError((_) {}); // schema no crítico
  }

  /// Extrae { ALIAS_UPPER → TABLA_REAL_UPPER } del texto completo del documento.
  /// Detecta: FROM tabla [alias], FROM tabla AS alias, JOIN tabla [alias]
  Map<String, String> _extractFromTables(String sql) {
    final result = <String, String>{};

    void add(String table, String? alias) {
      final t = table.toUpperCase();
      result[t] = t;
      if (alias != null && alias.isNotEmpty) {
        result[alias.toUpperCase()] = t;
      }
    }

    // FROM ... hasta WHERE/GROUP/ORDER/HAVING o fin (multi-línea)
    final fromBlock =
        RegExp(
          r'FROM\s+([\s\S]*?)(?=\bWHERE\b|\bGROUP\b|\bORDER\b|\bHAVING\b|$)',
          caseSensitive: false,
        ).firstMatch(sql)?.group(1) ??
        '';

    // Cada "tabla [AS] alias" separado por coma o espacio
    for (final m in RegExp(
      r'\b(\w+)\s+(?:AS\s+)?(\w+)\b',
      caseSensitive: false,
    ).allMatches(fromBlock)) {
      final candidate = m.group(2)!.toUpperCase();
      // Excluir palabras reservadas como alias
      const reserved = {
        'ON',
        'WHERE',
        'SET',
        'AND',
        'OR',
        'JOIN',
        'LEFT',
        'RIGHT',
        'INNER',
        'OUTER',
        'FULL',
        'CROSS',
        'GROUP',
        'ORDER',
        'HAVING',
      };
      if (!reserved.contains(candidate)) {
        add(m.group(1)!, m.group(2));
      }
    }

    // Solo nombre sin alias
    for (final m in RegExp(
      r'\bFROM\s+(\w+)(?:\s*,|\s*$|\s+(?:WHERE|GROUP|ORDER|HAVING|JOIN))',
      caseSensitive: false,
    ).allMatches(sql)) {
      add(m.group(1)!, null);
    }

    // JOINs: JOIN tabla [AS] alias
    for (final m in RegExp(
      r'\bJOIN\s+(\w+)(?:\s+AS\s+|\s+)(\w+)?',
      caseSensitive: false,
    ).allMatches(sql)) {
      add(m.group(1)!, m.group(2));
    }

    return result;
  }

  /// Devuelve la palabra que está escribiendo el usuario al final de la línea.
  String _wordBefore(String line) {
    final match = RegExp(r'(\w+)$').firstMatch(line);
    return match?.group(1) ?? '';
  }

  void _onEditorThemeChanged() {
    _ctrl?.setTheme(editorThemeStore.monacoTheme);
  }

  Future<void> _registerVariableCompletions() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    await _variablesReg?.dispose();
    _variablesReg = null;
    final vars = _filteredVariables();
    if (vars.isEmpty) return;
    final items = [
      for (final v in vars)
        CompletionItem(
          label: ':${v.cdVariable}',
          kind: CompletionItemKind.variable,
          detail: v.deVariable,
          documentation: v.deVariable,
          insertText: ':${v.cdVariable}',
        ),
    ];
    _variablesReg = await ctrl.registerStaticCompletions(
      id: 'plsql-variables',
      languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
      triggerCharacters: [':', ' ', '.', '('],
      items: items,
    );
  }

  // ── Guardar ────────────────────────────────────────────────────────────

  Future<void> _saveCurrentDocument() async {
    final onSave = widget.onSave;
    if (onSave == null || _saveStatus == _SaveStatus.saving) return;
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final code = await ctrl.document.getText();
    if (!mounted) return;
    setState(() => _saveStatus = _SaveStatus.saving);
    _saveTimer?.cancel();
    try {
      await onSave(code);
      if (!mounted) return;
      // Update deTexto in the open procs list so diff shows correct baseline
      final id = _activeProcId;
      if (id != null) {
        final idx = _openProcs.indexWhere((p) => p.cdProcedimiento == id);
        if (idx != -1) {
          setState(
            () => _openProcs[idx] = _openProcs[idx].copyWith(deTexto: code),
          );
        }
        setState(() {
          _modifiedProcs.remove(id);
          _draftVisible.remove(id);
        });
        _draftDebounce?.cancel();
        unawaited(EditorDraftService.clear(id, widget.ambiente));
      }
      widget.onDirtyChanged?.call(false);
      setState(() => _saveStatus = _SaveStatus.saved);
      _saveTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveStatus = _SaveStatus.error);
      _saveTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
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

  void _onContentChanged(String code) {
    _editorFullText =
        code; // mantener texto completo para el completion por FROM
    widget.onCodeChanged?.call(code);
    final id = _activeProcId;
    if (id != null && !_modifiedProcs.contains(id)) {
      setState(() => _modifiedProcs.add(id));
      widget.onDirtyChanged?.call(true);
    }
    _scheduleCheck(code);
    _scheduleDraftSave(id, code);
  }

  void _scheduleDraftSave(String? id, String code) {
    if (id == null) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 1500), () {
      EditorDraftService.save(id, widget.ambiente, code);
    });
  }

  Future<void> _discardDraft(String procId) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final proc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == procId,
      orElse: () => widget.procedimiento,
    );
    final doc = _docs[procId];
    if (doc != null) {
      await doc.setText(proc.deTexto);
    }
    _draftDebounce?.cancel();
    await EditorDraftService.clear(procId, widget.ambiente);
    if (!mounted) return;
    setState(() {
      _draftVisible.remove(procId);
      _modifiedProcs.remove(procId);
    });
    widget.onDirtyChanged?.call(false);
  }

  void _resetAllOptions() {
    setState(() {
      _minimap = true;
      _lineNumbers = true;
      _folding = true;
      _readOnly = false;
      _fontSize = 14.0;
      _wordWrap = false;
      _renderWhitespace = false;
      _bracketPairColorization = true;
      _stickyScroll = true;
      _smoothScrolling = false;
      _mouseWheelZoom = false;
      _formatOnPaste = false;
      _quickSuggestions = true;
      _parameterHints = true;
      _hover = true;
      _links = true;
      _occurrencesHighlight = true;
      _contextMenu = true;
    });
    _applyEditorOptions();
    _savePrefs();
  }

  // ── Persistencia de opciones ───────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _minimap = prefs.getBool('editor_minimap') ?? true;
      _lineNumbers = prefs.getBool('editor_line_numbers') ?? true;
      _folding = prefs.getBool('editor_folding') ?? true;
      _readOnly = prefs.getBool('editor_readonly') ?? false;
      _fontSize = prefs.getDouble('editor_font_size') ?? 14.0;
      _wordWrap = prefs.getBool('editor_word_wrap') ?? false;
      _renderWhitespace = prefs.getBool('editor_render_whitespace') ?? false;
      _bracketPairColorization =
          prefs.getBool('editor_bracket_colorization') ?? true;
      _stickyScroll = prefs.getBool('editor_sticky_scroll') ?? true;
      _smoothScrolling = prefs.getBool('editor_smooth_scrolling') ?? false;
      _mouseWheelZoom = prefs.getBool('editor_mouse_wheel_zoom') ?? false;
      _formatOnPaste = prefs.getBool('editor_format_on_paste') ?? false;
      _quickSuggestions = prefs.getBool('editor_quick_suggestions') ?? true;
      _parameterHints = prefs.getBool('editor_parameter_hints') ?? true;
      _hover = prefs.getBool('editor_hover') ?? true;
      _links = prefs.getBool('editor_links') ?? true;
      _occurrencesHighlight =
          prefs.getBool('editor_occurrences_highlight') ?? true;
      _contextMenu = prefs.getBool('editor_context_menu') ?? true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('editor_minimap', _minimap);
    await prefs.setBool('editor_line_numbers', _lineNumbers);
    await prefs.setBool('editor_folding', _folding);
    await prefs.setBool('editor_readonly', _readOnly);
    await prefs.setDouble('editor_font_size', _fontSize);
    await prefs.setBool('editor_word_wrap', _wordWrap);
    await prefs.setBool('editor_render_whitespace', _renderWhitespace);
    await prefs.setBool(
      'editor_bracket_colorization',
      _bracketPairColorization,
    );
    await prefs.setBool('editor_sticky_scroll', _stickyScroll);
    await prefs.setBool('editor_smooth_scrolling', _smoothScrolling);
    await prefs.setBool('editor_mouse_wheel_zoom', _mouseWheelZoom);
    await prefs.setBool('editor_format_on_paste', _formatOnPaste);
    await prefs.setBool('editor_quick_suggestions', _quickSuggestions);
    await prefs.setBool('editor_parameter_hints', _parameterHints);
    await prefs.setBool('editor_hover', _hover);
    await prefs.setBool('editor_links', _links);
    await prefs.setBool('editor_occurrences_highlight', _occurrencesHighlight);
    await prefs.setBool('editor_context_menu', _contextMenu);
  }

  void _applyEditorOptions() {
    _ctrl?.updateOptions(
      EditorOptions(
        minimap: MonacoMinimapOptions(enabled: _minimap),
        lineNumbers: _lineNumbers
            ? MonacoLineNumbers.on
            : MonacoLineNumbers.off,
        folding: _folding,
        readOnly: _readOnly,
        fontSize: _fontSize,
        wordWrap: _wordWrap ? MonacoWordWrap.on : MonacoWordWrap.off,
        renderWhitespace: _renderWhitespace
            ? RenderWhitespace.all
            : RenderWhitespace.none,
        bracketPairColorization: _bracketPairColorization,
        stickyScroll: MonacoStickyScroll(enabled: _stickyScroll),
        smoothScrolling: _smoothScrolling,
        mouseWheelZoom: _mouseWheelZoom,
        formatOnPaste: _formatOnPaste,
        quickSuggestions: _quickSuggestions,
        parameterHints: _parameterHints,
        hover: _hover,
        links: _links,
        occurrencesHighlight: _occurrencesHighlight,
        contextMenu: _contextMenu,
      ),
    );
  }

  void _toggle(VoidCallback fn) {
    setState(fn);
    _applyEditorOptions();
    _savePrefs();
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

        // Banner de solo lectura
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _readOnly
              ? Container(
                  key: const ValueKey('readonly'),
                  width: double.infinity,
                  color: Colors.amber.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 13,
                        color: Colors.amber[700],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Editor en modo solo lectura — los cambios no se aplicarán',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber[700],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('noreadonly')),
        ),

        // Draft restore banner
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _draftVisible[_activeProcId] == true
              ? Container(
                  key: const ValueKey('draft'),
                  width: double.infinity,
                  color: const Color(0xFF0078D4).withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.restore_rounded,
                        size: 13,
                        color: Color(0xFF0078D4),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Borrador sin guardar restaurado',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF0078D4),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _discardDraft(_activeProcId!),
                        child: const Text(
                          'Descartar',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF0078D4),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('nodraft')),
        ),

        // Editor Monaco + overlay de schema
        Expanded(
          child: Stack(
            children: [
              MonacoEditor(
                initialText: widget.procedimiento.deTexto,
                options: EditorOptions(
                  language: _langFor(widget.procedimiento),
                  theme: oracleDarkTheme,
                  fontSize: _fontSize,
                  minimap: MonacoMinimapOptions(enabled: _minimap),
                  wordWrap: _wordWrap ? MonacoWordWrap.on : MonacoWordWrap.off,
                  lineNumbers: _lineNumbers
                      ? MonacoLineNumbers.on
                      : MonacoLineNumbers.off,
                  renderWhitespace: _renderWhitespace
                      ? RenderWhitespace.all
                      : RenderWhitespace.none,
                  tabSize: 2,
                  bracketPairColorization: _bracketPairColorization,
                  stickyScroll: MonacoStickyScroll(enabled: _stickyScroll),
                  folding: _folding,
                  readOnly: _readOnly,
                  smoothScrolling: _smoothScrolling,
                  mouseWheelZoom: _mouseWheelZoom,
                  formatOnPaste: _formatOnPaste,
                  quickSuggestions: _quickSuggestions,
                  parameterHints: _parameterHints,
                  hover: _hover,
                  links: _links,
                  occurrencesHighlight: _occurrencesHighlight,
                  contextMenu: _contextMenu,
                ),
                showStatusBar: true,
                page: const MonacoPageConfig(
                  customCss:
                      '.plsql-error-line { background: rgba(255,68,68,0.1) !important; }',
                ),
                contentDebounce: const Duration(milliseconds: 400),
                onReady: _onReady,
                onContentChanged: _onContentChanged,
                onError: (err, _) => debugPrint('Monaco error: $err'),
              ),

              // Overlay flotante — indicador de schema (esquina inferior izquierda)
            ],
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
            isModified: _modifiedProcs.contains(proc.cdProcedimiento),
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
      height: 36,
      color: isDark ? cs.surfaceContainerLow : cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          // ── Toggles principales ─────────────────────────────────────────
          _ToggleBtn(
            icon: Icons.map_outlined,
            tooltip: 'Minimap',
            active: _minimap,
            onPressed: () => _toggle(() => _minimap = !_minimap),
          ),
          _ToggleBtn(
            icon: Icons.format_list_numbered,
            tooltip: 'Número de líneas',
            active: _lineNumbers,
            onPressed: () => _toggle(() => _lineNumbers = !_lineNumbers),
          ),
          _ToggleBtn(
            icon: _folding ? Icons.unfold_less : Icons.unfold_more,
            tooltip: 'Colapsar bloques',
            active: _folding,
            onPressed: () => _toggle(() => _folding = !_folding),
          ),
          _ToggleBtn(
            icon: _readOnly ? Icons.lock_outline : Icons.lock_open,
            tooltip: 'Solo lectura — bloquear edición',
            active: _readOnly,
            onPressed: () => _toggle(() => _readOnly = !_readOnly),
          ),
          const SizedBox(width: 4),
          // ── Control de zoom (pill) ─────────────────────────────────
          Container(
            height: 26,
            decoration: BoxDecoration(
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.7),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Reducir fuente (Ctrl+−)',
                  waitDuration: _kTooltipWait,
                  preferBelow: false,
                  decoration: _kTooltipDecoration,
                  textStyle: _kTooltipTextStyle,
                  child: InkWell(
                    onTap: _fontSize > 10
                        ? () => _toggle(
                            () => _fontSize = (_fontSize - 2).clamp(10, 28),
                          )
                        : null,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(13),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Icon(
                        Icons.remove,
                        size: 14,
                        color: _fontSize > 10
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${_fontSize.toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Aumentar fuente (Ctrl+=)',
                  waitDuration: _kTooltipWait,
                  preferBelow: false,
                  decoration: _kTooltipDecoration,
                  textStyle: _kTooltipTextStyle,
                  child: InkWell(
                    onTap: _fontSize < 28
                        ? () => _toggle(
                            () => _fontSize = (_fontSize + 2).clamp(10, 28),
                          )
                        : null,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(13),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Icon(
                        Icons.add,
                        size: 14,
                        color: _fontSize < 28
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          // ── Opciones adicionales ─────────────────────────────────────────
          _buildOptionsGear(cs),
          _buildVarsButton(cs),
          const Spacer(),
          // ── Badge de errores ──────────────────────────────────────────────
          _buildErrorBadge(cs),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          // ── Guardar / Acciones ───────────────────────────────────────────
          _buildSaveBtn(cs),
          _ToolBtn(
            icon: Icons.compare_arrows,
            tooltip: 'Ver diff vs. versión guardada (sin guardar)',
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

  Widget _buildSaveBtn(ColorScheme cs) {
    return switch (_saveStatus) {
      _SaveStatus.saving => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF0078D4),
          ),
        ),
      ),
      _SaveStatus.saved => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 14,
              color: Colors.green[600],
            ),
            const SizedBox(width: 4),
            Text(
              'Guardado',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      _SaveStatus.error => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
            const SizedBox(width: 4),
            Text(
              'Error',
              style: TextStyle(fontSize: 11, color: Colors.red[400]),
            ),
          ],
        ),
      ),
      _SaveStatus.idle => _buildSaveBtnIdle(cs),
    };
  }

  Widget _buildSaveBtnIdle(ColorScheme cs) {
    final isDirty = _modifiedProcs.contains(_activeProcId);
    final canSave = widget.onSave != null;
    return Tooltip(
      message: 'Guardar (Ctrl+S)',
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: canSave ? _saveCurrentDocument : null,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isDirty
                ? const Color(0xFF0078D4).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isDirty
                ? Border.all(
                    color: const Color(0xFF0078D4).withValues(alpha: 0.4),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.save_outlined,
                size: 15,
                color: isDirty
                    ? const Color(0xFF0078D4)
                    : cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              if (isDirty) ...[
                const SizedBox(width: 4),
                const Text(
                  'Guardar',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF0078D4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVarsButton(ColorScheme cs) {
    final vars = _filteredVariables();
    if (vars.isEmpty) return const SizedBox();
    return Tooltip(
      message: 'Variables dinámicas (${vars.length})',
      waitDuration: _kTooltipWait,
      preferBelow: true,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        key: _varsButtonKey,
        borderRadius: BorderRadius.circular(4),
        onTap: () => _showVarsOverlay(vars),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Badge(
            label: Text('${vars.length}', style: const TextStyle(fontSize: 10)),
            child: Icon(
              Icons.data_object,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _showVarsOverlay(List<VariableDinamica> vars) {
    final box = _varsButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset(0, box.size.height + 4));
    final screenW = MediaQuery.sizeOf(context).width;
    const panelW = 300.0;
    final left = (anchor.dx + panelW > screenW)
        ? screenW - panelW - 8
        : anchor.dx;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'vars-dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) => _VarsMenuOverlay(
        left: left,
        top: anchor.dy,
        width: panelW,
        vars: vars,
        onSelected: (v) async {
          final ctrl = _ctrl;
          if (ctrl == null) return;
          final pos = await ctrl.getCursorPosition();
          if (pos != null) await ctrl.document.insert(pos, ':${v.cdVariable}');
        },
      ),
    );
  }

  Widget _buildErrorBadge(ColorScheme cs) {
    final n = _errorCounts[_activeProcId] ?? 0;
    final issues = _issuesPerProc[_activeProcId] ?? [];

    final badge = Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: n > 0
            ? Colors.red.withValues(alpha: 0.12)
            : Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: n > 0
              ? Colors.red.withValues(alpha: 0.45)
              : Colors.green.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            n > 0 ? Icons.error_outline : Icons.check_circle_outline,
            size: 12,
            color: n > 0 ? Colors.red[400] : Colors.green[600],
          ),
          const SizedBox(width: 4),
          Text(
            n > 0 ? '$n' : 'OK',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: n > 0 ? Colors.red[400] : Colors.green[600],
            ),
          ),
        ],
      ),
    );

    if (n == 0) {
      return Tooltip(
        message: 'Sin errores de sintaxis',
        waitDuration: _kTooltipWait,
        preferBelow: false,
        decoration: _kTooltipDecoration,
        textStyle: _kTooltipTextStyle,
        child: badge,
      );
    }

    return Tooltip(
      message: 'Clic para navegar a los errores',
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: PopupMenuButton<PlSqlIssue>(
        tooltip: '',
        padding: EdgeInsets.zero,
        onSelected: (e) async {
          await _ctrl?.revealLine(e.line, center: true);
          await _ctrl?.setCursorPosition(Position(line: e.line, column: e.col));
        },
        itemBuilder: (_) => [
          for (final e in issues)
            PopupMenuItem<PlSqlIssue>(
              value: e,
              height: 44,
              child: _ErrorItem(issue: e),
            ),
        ],
        child: badge,
      ),
    );
  }

  Widget _buildOptionsGear(ColorScheme cs) {
    final headerStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      letterSpacing: 0.8,
    );
    return PopupMenuButton<_EditorOption>(
      tooltip: 'Más opciones del editor',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.tune, size: 16, color: cs.onSurfaceVariant),
      onSelected: (_EditorOption opt) {
        if (opt == _EditorOption.resetDefaults) {
          _resetAllOptions();
          return;
        }
        _toggle(() {
          switch (opt) {
            case _EditorOption.wordWrap:
              _wordWrap = !_wordWrap;
            case _EditorOption.renderWhitespace:
              _renderWhitespace = !_renderWhitespace;
            case _EditorOption.bracketColorize:
              _bracketPairColorization = !_bracketPairColorization;
            case _EditorOption.stickyScroll:
              _stickyScroll = !_stickyScroll;
            case _EditorOption.smoothScrolling:
              _smoothScrolling = !_smoothScrolling;
            case _EditorOption.mouseWheelZoom:
              _mouseWheelZoom = !_mouseWheelZoom;
            case _EditorOption.formatOnPaste:
              _formatOnPaste = !_formatOnPaste;
            case _EditorOption.quickSuggestions:
              _quickSuggestions = !_quickSuggestions;
            case _EditorOption.parameterHints:
              _parameterHints = !_parameterHints;
            case _EditorOption.hover:
              _hover = !_hover;
            case _EditorOption.links:
              _links = !_links;
            case _EditorOption.occurrences:
              _occurrencesHighlight = !_occurrencesHighlight;
            case _EditorOption.contextMenu:
              _contextMenu = !_contextMenu;
            case _EditorOption.resetDefaults:
              break;
          }
        });
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('VISUALIZACIÓN', style: headerStyle),
        ),
        _optItem(_EditorOption.wordWrap, 'Ajuste de línea', _wordWrap),
        _optItem(
          _EditorOption.renderWhitespace,
          'Mostrar espacios/tabs',
          _renderWhitespace,
        ),
        _optItem(
          _EditorOption.bracketColorize,
          'Colorizar paréntesis',
          _bracketPairColorization,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('SCROLL', style: headerStyle),
        ),
        _optItem(_EditorOption.stickyScroll, 'Scroll pegajoso', _stickyScroll),
        _optItem(
          _EditorOption.smoothScrolling,
          'Scroll suave',
          _smoothScrolling,
        ),
        _optItem(
          _EditorOption.mouseWheelZoom,
          'Zoom con rueda del ratón',
          _mouseWheelZoom,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('EDICIÓN', style: headerStyle),
        ),
        _optItem(
          _EditorOption.formatOnPaste,
          'Formatear al pegar',
          _formatOnPaste,
        ),
        _optItem(
          _EditorOption.quickSuggestions,
          'Sugerencias automáticas',
          _quickSuggestions,
        ),
        _optItem(
          _EditorOption.parameterHints,
          'Hints de parámetros',
          _parameterHints,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('INTERFAZ', style: headerStyle),
        ),
        _optItem(_EditorOption.hover, 'Tooltips hover', _hover),
        _optItem(_EditorOption.links, 'Links clicables', _links),
        _optItem(
          _EditorOption.occurrences,
          'Resaltar ocurrencias',
          _occurrencesHighlight,
        ),
        _optItem(_EditorOption.contextMenu, 'Menú contextual', _contextMenu),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          value: _EditorOption.resetDefaults,
          child: Row(
            children: [
              Icon(
                Icons.refresh,
                size: 14,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              const Text(
                'Restablecer predeterminados',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  CheckedPopupMenuItem<_EditorOption> _optItem(
    _EditorOption value,
    String label,
    bool checked,
  ) {
    return CheckedPopupMenuItem<_EditorOption>(
      value: value,
      checked: checked,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────

const _kTooltipDecoration = BoxDecoration(
  color: Color(0xFF2D2D30),
  borderRadius: BorderRadius.all(Radius.circular(6)),
  boxShadow: [
    BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
  ],
);
const _kTooltipTextStyle = TextStyle(color: Colors.white, fontSize: 12);
const _kTooltipWait = Duration(milliseconds: 400);

class _DocTab extends StatelessWidget {
  final Procedimiento proc;
  final bool isActive;
  final bool isModified;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _DocTab({
    required this.proc,
    required this.isActive,
    required this.isModified,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
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
            if (isModified)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '●',
                  style: TextStyle(fontSize: 9, color: cs.primary, height: 1.2),
                ),
              ),
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
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;

  const _ToggleBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

enum _EditorOption {
  wordWrap,
  renderWhitespace,
  bracketColorize,
  stickyScroll,
  smoothScrolling,
  mouseWheelZoom,
  formatOnPaste,
  quickSuggestions,
  parameterHints,
  hover,
  links,
  occurrences,
  contextMenu,
  resetDefaults,
}

class _ErrorItem extends StatelessWidget {
  final PlSqlIssue issue;

  const _ErrorItem({required this.issue});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Línea ${issue.line}, col ${issue.col}',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                issue.message,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Overlay de variables dinámicas con buscador ──────────────────────────────

class _VarsMenuOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final List<VariableDinamica> vars;
  final Future<void> Function(VariableDinamica) onSelected;

  const _VarsMenuOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.vars,
    required this.onSelected,
  });

  @override
  State<_VarsMenuOverlay> createState() => _VarsMenuOverlayState();
}

class _VarsMenuOverlayState extends State<_VarsMenuOverlay> {
  final _search = TextEditingController();
  late List<VariableDinamica> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.vars;
    _search.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.vars
          : widget.vars
                .where(
                  (v) =>
                      v.cdVariable.toLowerCase().contains(q) ||
                      v.deVariable.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : cs.surface;
    final borderColor = isDark ? const Color(0xFF3C3C3C) : cs.outlineVariant;

    return Stack(
      children: [
        Positioned(
          left: widget.left,
          top: widget.top,
          width: widget.width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Buscar variable…',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 0,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E1E1E)
                              : cs.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: borderColor,
                              width: 0.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: borderColor,
                              width: 0.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: cs.primary, width: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: borderColor),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Sin resultados',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final v = _filtered[i];
                          return InkWell(
                            onTap: () async {
                              Navigator.of(context).pop();
                              await widget.onSelected(v);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          ':${v.cdVariable}',
                                          style: TextStyle(
                                            fontFamily: 'Consolas',
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: cs.primary,
                                          ),
                                        ),
                                        if (v.deVariable.isNotEmpty)
                                          Text(
                                            v.deVariable,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_return,
                                    size: 12,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
