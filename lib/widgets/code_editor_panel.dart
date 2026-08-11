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
import 'app_toast.dart';

part '_editor_toolbar_widgets.dart';
part '_editor_variables_overlay.dart';

enum _SaveStatus { idle, saving, saved, error }

enum _CompileStatus { idle, compiling, ok, error }

class CodeEditorPanel extends StatefulWidget {
  final Procedimiento procedimiento;
  final String ambiente;
  final ValueChanged<bool>? onDirtyChanged;
  final Future<void> Function(String code)? onSave;
  final Future<void> Function(String code)? onCompile;
  final ValueChanged<String>? onCodeChanged;

  const CodeEditorPanel({
    super.key,
    required this.procedimiento,
    required this.ambiente,
    this.onDirtyChanged,
    this.onSave,
    this.onCompile,
    this.onCodeChanged,
  });

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  // Compiled once — reused on every completion keystroke and FROM-clause parse
  static final _reDotPrefix = RegExp(r'(\w+)\.$');
  static final _reWordEnd = RegExp(r'(\w+)$');
  static final _reFromBlock = RegExp(
    r'FROM\s+([\s\S]*?)(?=\bWHERE\b|\bGROUP\b|\bORDER\b|\bHAVING\b|$)',
    caseSensitive: false,
  );
  static final _reAliasBlock = RegExp(
    r'\b(\w+)\s+(?:AS\s+)?(\w+)\b',
    caseSensitive: false,
  );
  static final _reFromSimple = RegExp(
    r'\bFROM\s+(\w+)(?:\s*,|\s*$|\s+(?:WHERE|GROUP|ORDER|HAVING|JOIN))',
    caseSensitive: false,
  );
  static final _reJoin = RegExp(
    r'\bJOIN\s+(\w+)(?:\s+AS\s+|\s+)(\w+)?',
    caseSensitive: false,
  );

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
  String _editorFullText = '';
  // Cache for _extractFromTables — avoids regex on full text for each keystroke
  int? _fromExtractHash;
  Map<String, String> _fromExtractResult = {};
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
  final Map<String, List<PlSqlIssue>> _compileErrorsPerProc = {};
  MonacoActionRegistration? _zoomInAction;
  MonacoActionRegistration? _zoomOutAction;
  MonacoActionRegistration? _saveAction;
  MonacoActionRegistration? _compileAction;
  Timer? _saveTimer;
  Timer? _draftDebounce;
  _SaveStatus _saveStatus = _SaveStatus.idle;
  _CompileStatus _compileStatus = _CompileStatus.idle;
  String? _lastSaveError;
  bool _showProblemsPanel = false;
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
    if (old.ambiente != widget.ambiente) {
      AppToast.info('Ambiente cambiado a ${widget.ambiente}');
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
    _compileAction?.dispose();
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

    _compileAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.compile'),
        label: 'Compilar procedimiento (Oracle)',
        keybindings: [MonacoKeybinding(key: MonacoKey.f5)],
      ),
      () async {
        unawaited(_compileCurrentDocument());
      },
    );

    if (mounted) setState(() {});

    // Delay ANTLR injection so 6MB JS eval doesn't block initial typing
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _ctrl != null) _injectAntlrBundle(_ctrl!);
    });
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
      const Duration(milliseconds: 1200),
      () => _checkPlSql(code),
    );
  }

  Future<void> _checkPlSql(String code) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    List<PlSqlIssue> issues;
    // Skip ANTLR for very large files — Dart fallback is much faster
    if (_antlrReady && code.length < 40000) {
      try {
        // Read text directly from Monaco model — avoids jsonEncode + bridge transfer
        final raw = await ctrl.evaluateJavaScript<String>(
          'try{__checkPlSql(_editor.getValue())}catch(e){null}',
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
        final compileErrors = _compileErrorsPerProc[id] ?? [];
        _issuesPerProc[id] = issues;
        // Mantener el total combinado sintaxis + Oracle al actualizar
        _errorCounts[id] = [
          ...issues,
          ...compileErrors,
        ].where((e) => e.severity == MarkerSeverity.error).length;
      });
    }

    // Markers — squiggles rojos en el texto (sintaxis + errores de compilación Oracle)
    await ctrl.document.setMarkers([
      for (final e in [
        ...issues,
        ...(_compileErrorsPerProc[_activeProcId ?? ''] ?? []),
      ])
        MarkerData(
          range: Range(
            startLine: e.line,
            startColumn: e.col,
            endLine: e.line,
            endColumn: e.endCol,
          ),
          message: e.message,
          severity: e.severity,
          source: e.source,
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
                final dotMatch = _reDotPrefix.firstMatch(line);
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
    final hash = sql.hashCode ^ sql.length;
    if (hash == _fromExtractHash) return _fromExtractResult;
    final result = <String, String>{};

    void add(String table, String? alias) {
      final t = table.toUpperCase();
      result[t] = t;
      if (alias != null && alias.isNotEmpty) {
        result[alias.toUpperCase()] = t;
      }
    }

    // FROM ... hasta WHERE/GROUP/ORDER/HAVING o fin (multi-línea)
    final fromBlock = _reFromBlock.firstMatch(sql)?.group(1) ?? '';

    // Cada "tabla [AS] alias" separado por coma o espacio
    for (final m in _reAliasBlock.allMatches(fromBlock)) {
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
    for (final m in _reFromSimple.allMatches(sql)) {
      add(m.group(1)!, null);
    }

    // JOINs: JOIN tabla [AS] alias
    for (final m in _reJoin.allMatches(sql)) {
      add(m.group(1)!, m.group(2));
    }

    _fromExtractHash = sql.hashCode ^ sql.length;
    _fromExtractResult = result;
    return result;
  }

  /// Devuelve la palabra que está escribiendo el usuario al final de la línea.
  String _wordBefore(String line) {
    final match = _reWordEnd.firstMatch(line);
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
      // Apply Oracle compile errors returned by the server as Monaco markers
      final rawCompileErrors = procedimientosProvider.lastCompileErrors;
      final procId = _activeProcId ?? '';
      if (rawCompileErrors.isNotEmpty && mounted) {
        final compileIssues = parseOracleCompileErrors(rawCompileErrors);
        setState(() {
          _compileErrorsPerProc[procId] = compileIssues;
          _errorCounts[procId] =
              ((_issuesPerProc[procId] ?? []) + compileIssues)
                  .where((e) => e.severity == MarkerSeverity.error)
                  .length;
        });
        final syntaxIssues = _issuesPerProc[procId] ?? [];
        final ctrl = _ctrl;
        if (ctrl != null) {
          await ctrl.document.setMarkers([
            for (final e in [...syntaxIssues, ...compileIssues])
              MarkerData(
                range: Range(
                  startLine: e.line,
                  startColumn: e.col,
                  endLine: e.line,
                  endColumn: e.endCol,
                ),
                message: e.message,
                severity: e.severity,
                source: e.source,
              ),
          ], owner: 'plsql-checker');
        }
        AppToast.warning(
          '${compileIssues.length} error${compileIssues.length == 1 ? '' : 'es'} de compilación Oracle',
        );
        if (mounted) setState(() => _showProblemsPanel = true);
      } else if (mounted && _compileErrorsPerProc.containsKey(procId)) {
        // Clear previous compile errors on a now-clean save
        setState(() => _compileErrorsPerProc.remove(procId));
        final ctrl = _ctrl;
        final syntaxIssues = _issuesPerProc[procId] ?? [];
        if (ctrl != null) {
          await ctrl.document.setMarkers([
            for (final e in syntaxIssues)
              MarkerData(
                range: Range(
                  startLine: e.line,
                  startColumn: e.col,
                  endLine: e.line,
                  endColumn: e.endCol,
                ),
                message: e.message,
                severity: e.severity,
                source: e.source,
              ),
          ], owner: 'plsql-checker');
        }
      }
      setState(() => _saveStatus = _SaveStatus.saved);
      _saveTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[CodeEditorPanel] Error al guardar: $msg');
      if (!mounted) return;
      // Intentar parsear como errores Oracle estructurados; si no, crear uno genérico
      final procId = _activeProcId ?? '';
      final parsed = parseOracleCompileErrors(msg);
      final serverErrors = parsed.isNotEmpty
          ? parsed
          : [
              PlSqlIssue(
                line: 1,
                col: 1,
                endCol: 2,
                message: msg,
                source: 'Oracle',
              ),
            ];
      setState(() {
        _saveStatus = _SaveStatus.error;
        _lastSaveError = msg;
        _compileErrorsPerProc[procId] = serverErrors;
        _errorCounts[procId] = ((_issuesPerProc[procId] ?? []) + serverErrors)
            .where((e) => e.severity == MarkerSeverity.error)
            .length;
        _showProblemsPanel = true;
      });
      // Aplicar squiggles y decoraciones en Monaco para ver los errores en el código
      final editorCtrl = _ctrl;
      if (editorCtrl != null) {
        final syntaxIssues = _issuesPerProc[procId] ?? [];
        await editorCtrl.document.setMarkers([
          for (final e in [...syntaxIssues, ...serverErrors])
            MarkerData(
              range: Range(
                startLine: e.line,
                startColumn: e.col,
                endLine: e.line,
                endColumn: e.endCol,
              ),
              message: e.message,
              severity: e.severity,
              source: e.source,
            ),
        ], owner: 'plsql-checker');
        await _errorDecos?.set([
          for (final e in serverErrors)
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
      _saveTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
    }
  }

  // ── Compilar (usa el ANTLR4/Oracle del servidor) ─────────────────────

  Future<void> _compileCurrentDocument() async {
    final onCompile = widget.onCompile;
    if (onCompile == null || _compileStatus == _CompileStatus.compiling) return;
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final code = await ctrl.document.getText();
    if (!mounted) return;
    setState(() => _compileStatus = _CompileStatus.compiling);
    try {
      await onCompile(code);
      if (!mounted) return;
      final rawCompileErrors = procedimientosProvider.lastCompileErrors;
      final procId = _activeProcId ?? '';
      if (rawCompileErrors.isNotEmpty) {
        final compileIssues = parseOracleCompileErrors(rawCompileErrors);
        final syntaxIssues = _issuesPerProc[procId] ?? [];
        setState(() {
          _compileErrorsPerProc[procId] = compileIssues;
          _errorCounts[procId] = ([
            ...syntaxIssues,
            ...compileIssues,
          ]).where((e) => e.severity == MarkerSeverity.error).length;
          _compileStatus = _CompileStatus.error;
          _showProblemsPanel = true;
        });
        await ctrl.document.setMarkers([
          for (final e in [...syntaxIssues, ...compileIssues])
            MarkerData(
              range: Range(
                startLine: e.line,
                startColumn: e.col,
                endLine: e.line,
                endColumn: e.endCol,
              ),
              message: e.message,
              severity: e.severity,
              source: e.source,
            ),
        ], owner: 'plsql-checker');
        await _errorDecos?.set([
          for (final e in compileIssues)
            DecorationOptions.line(
              range: Range.lines(e.line, e.line),
              className: 'plsql-error-line',
              additionalOptions: {
                'overviewRuler': {'color': '#FF4444', 'position': 4},
                'minimap': {'color': '#FF4444', 'position': 1},
              },
            ),
        ]);
      } else {
        if (_compileErrorsPerProc.containsKey(procId)) {
          setState(() => _compileErrorsPerProc.remove(procId));
        }
        setState(() => _compileStatus = _CompileStatus.ok);
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[CodeEditorPanel] Error al compilar: $msg');
      if (!mounted) return;
      final procId = _activeProcId ?? '';
      final parsed = parseOracleCompileErrors(msg);
      final errors = parsed.isNotEmpty
          ? parsed
          : [
              PlSqlIssue(
                line: 1,
                col: 1,
                endCol: 2,
                message: msg,
                source: 'Oracle',
              ),
            ];
      setState(() {
        _compileStatus = _CompileStatus.error;
        _compileErrorsPerProc[procId] = errors;
        _errorCounts[procId] = ((_issuesPerProc[procId] ?? []) + errors)
            .where((e) => e.severity == MarkerSeverity.error)
            .length;
        _showProblemsPanel = true;
      });
    }
    Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _compileStatus = _CompileStatus.idle);
    });
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
                contentDebounce: const Duration(milliseconds: 600),
                onReady: _onReady,
                onContentChanged: _onContentChanged,
                onError: (err, _) => debugPrint('Monaco error: $err'),
              ),

              // Overlay flotante — indicador de schema (esquina inferior izquierda)
            ],
          ),
        ),
        // Panel de problemas (sintaxis + compilación Oracle)
        _buildProblemsPanel(context),
      ],
    );
  }

  Widget _buildProblemsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final procId = _activeProcId ?? '';
    final syntaxIssues = _issuesPerProc[procId] ?? [];
    final compileIssues = _compileErrorsPerProc[procId] ?? [];
    final allIssues = [...compileIssues, ...syntaxIssues]
      ..sort((a, b) => a.line.compareTo(b.line));
    final errorCount = allIssues
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final warnCount = allIssues
        .where((e) => e.severity == MarkerSeverity.warning)
        .length;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      child: _showProblemsPanel
          ? Container(
              height: 180,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : cs.surfaceContainerLow,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Column(
                children: [
                  Container(
                    height: 28,
                    color: isDark
                        ? cs.surfaceContainerHigh
                        : cs.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.list_alt_rounded,
                          size: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Problemas',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (errorCount > 0)
                          _ProblemCount(count: errorCount, isError: true),
                        if (warnCount > 0) ...[
                          const SizedBox(width: 4),
                          _ProblemCount(count: warnCount, isError: false),
                        ],
                        const Spacer(),
                        InkWell(
                          onTap: () =>
                              setState(() => _showProblemsPanel = false),
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: allIssues.isEmpty
                        ? Center(
                            child: Text(
                              'Sin problemas detectados',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: allIssues.length,
                            itemBuilder: (_, i) {
                              final issue = allIssues[i];
                              final isError =
                                  issue.severity == MarkerSeverity.error;
                              return InkWell(
                                onTap: () async {
                                  await _ctrl?.revealLine(
                                    issue.line,
                                    center: true,
                                  );
                                  await _ctrl?.setCursorPosition(
                                    Position(
                                      line: issue.line,
                                      column: issue.col,
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isError
                                            ? Icons.error_outline
                                            : Icons.warning_amber_rounded,
                                        size: 14,
                                        color: isError
                                            ? Colors.red[400]
                                            : Colors.orange[400],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          issue.message,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontFamily: 'Consolas',
                                          ),
                                          softWrap: true,
                                          maxLines: 4,
                                          overflow: TextOverflow.fade,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Solo mostrar L:C si tienen valores reales (>1)
                                      if (issue.line > 1 || issue.col > 1)
                                        Text(
                                          'L${issue.line}:${issue.col}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant,
                                            fontFamily: 'Consolas',
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Text(
                                          issue.source,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: issue.source == 'Oracle'
                                                ? Colors.orange[400]
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Copiar mensaje',
                                        child: InkWell(
                                          onTap: () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text:
                                                    '${issue.source} L${issue.line}:${issue.col} — ${issue.message}',
                                              ),
                                            );
                                            AppToast.info(
                                              'Copiado al portapapeles',
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(3),
                                            child: Icon(
                                              Icons.copy_rounded,
                                              size: 13,
                                              color: cs.onSurfaceVariant
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
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
            )
          : const SizedBox.shrink(),
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
          _buildCompileBtn(cs),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          const SizedBox(width: 4),
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

  Widget _buildCompileBtn(ColorScheme cs) {
    return switch (_compileStatus) {
      _CompileStatus.compiling => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF569CD6),
          ),
        ),
      ),
      _CompileStatus.ok => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.elasticOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 14, color: Colors.green[500]),
              const SizedBox(width: 4),
              Text(
                'Compilado',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      _CompileStatus.error => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: Colors.orange[400]),
            const SizedBox(width: 4),
            Text(
              'Errores',
              style: TextStyle(fontSize: 11, color: Colors.orange[400]),
            ),
          ],
        ),
      ),
      _CompileStatus.idle => Tooltip(
        message:
            'Compilar con Oracle — verifica errores sin guardar si falla (F5)',
        waitDuration: _kTooltipWait,
        preferBelow: false,
        decoration: _kTooltipDecoration,
        textStyle: _kTooltipTextStyle,
        child: InkWell(
          onTap: _compileCurrentDocument,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 15,
                  color: const Color(0xFF569CD6),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Compilar',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF569CD6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    };
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
      _SaveStatus.saved => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.elasticOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Padding(
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
      ),
      _SaveStatus.error => Tooltip(
        message: _lastSaveError ?? 'Error al guardar',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
              const SizedBox(width: 4),
              Text(
                'Error al guardar',
                style: TextStyle(fontSize: 11, color: Colors.red[400]),
              ),
            ],
          ),
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
    final procId = _activeProcId ?? '';
    final syntaxErrors = (_issuesPerProc[procId] ?? [])
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final compileErrors = (_compileErrorsPerProc[procId] ?? [])
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final n = syntaxErrors + compileErrors;
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
      message: _showProblemsPanel
          ? 'Ocultar panel de problemas'
          : 'Mostrar panel de problemas',
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: () => setState(() => _showProblemsPanel = !_showProblemsPanel),
        borderRadius: BorderRadius.circular(10),
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
