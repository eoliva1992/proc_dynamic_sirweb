import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;
import '../services/app_log.dart';
import '../services/schema_service.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import '_editor_themes.dart';
import 'ambiente_selector.dart';
import 'app_toast.dart';
import 'code_editor_panel.dart'
    show showInfoEventoWindow, showInfoDatoWindow, showAutorizacionesWindow;
import 'constellation_background.dart';
import 'monaco_snippets.dart';
import 'slide_up_panel.dart';
import 'source_tab_controller.dart';
import 'status_card.dart';

part '_source_widgets.dart';
part '_source_backup_dialog.dart';
part '_source_package_nav.dart';
part '_source_problems_panel.dart';
part '_source_monaco_tab.dart';
part '_source_multidoc_editor.dart';

const kTypeColors = {
  'TABLE': Color(0xFF0078D4),
  'VIEW': Color(0xFF107C10),
  'PROCEDURE': Color(0xFFCA5010),
  'FUNCTION': Color(0xFF8764B8),
  'PACKAGE': Color(0xFFC19C00),
  'TYPE': Color(0xFF2E7D9E),
};

const kTypeIcons = {
  'TABLE': Icons.table_chart_outlined,
  'VIEW': Icons.visibility_outlined,
  'PROCEDURE': Icons.code_rounded,
  'FUNCTION': Icons.functions_rounded,
  'PACKAGE': Icons.inventory_2_outlined,
  'TYPE': Icons.data_object_outlined,
};

enum _ViewerCompileStatus { idle, compiling, ok, error }

enum _CtxMenuAction { gotoDef, infoEvento, infoDato, cut, copy, paste }

// ── Guardas contra el editor ya destruido ────────────────────────────────────
// `flutter_monaco` lanza `MonacoDisposedError: MonacoController has been
// disposed.` cuando se toca el controller (o un documento/registro suyo)
// después de que el webview murió. Como casi todas las rutas de estos editores
// son asíncronas (debounce, validación en el backend, futures de schema), es
// normal que una operación en vuelo aterrice sobre un editor ya cerrado.

bool _isMonacoDisposedError(Object e) {
  final msg = e.toString();
  return msg.contains('MonacoDisposedError') ||
      msg.contains('has been disposed');
}

/// Libera un recurso de Monaco ignorando el fallo por editor ya destruido,
/// tanto síncrono como el del `Future` que pueda devolver.
void _disposeMonacoQuietly(Object? Function() action) {
  void report(Object e) {
    if (!_isMonacoDisposedError(e)) {
      debugPrint('[ObjectSourcePage] error al liberar recurso: $e');
    }
  }

  try {
    final result = action();
    if (result is Future) {
      result.catchError((Object e) {
        report(e);
        return null;
      });
    }
  } catch (e) {
    report(e);
  }
}

// Shared across all editor instances — avoids re-reading the asset each time
// _cachedAntlrJs removed — validation now uses Oracle backend

// flutter_monaco's pointerDown handler calls forceFocus() (JS) whenever
// Monaco reports blur, to reclaim native focus after clicking elsewhere.
// That handler's own idempotency guard only skips the document.body.focus()
// handoff when the editor's textarea already owns document.activeElement —
// it does NOT skip it while a right-click context menu owns focus instead,
// so clicking any context menu item (built-in or custom, e.g. "Ver
// definición Oracle") blurs-then-closes the menu before the click is
// processed by the browser. Patching the JS focus() calls forceFocus()
// actually uses (document.body, the editor, its textarea) to no-op while
// `.monaco-menu-container` is present in the DOM fixes this regardless of
// Dart-side widget rebuild timing. See the identical patch and rationale in
// code_editor_panel.dart's `_onReady`.
const String _kContextMenuFocusGuardJs =
    '(function(){'
    '  function isMenuOpen(){'
    '    return !!document.querySelector(".monaco-menu-container");'
    '  }'
    '  function patchEl(el){'
    '    if(!el||el._fp) return;'
    '    el._fp=true;'
    '    var o=el.focus.bind(el);'
    '    el.focus=function(opts){ if(!isMenuOpen()) o(opts); };'
    '  }'
    '  if(!document.body._fp){'
    '    document.body._fp=true;'
    '    var ob=document.body.focus.bind(document.body);'
    '    document.body.focus=function(){ if(!isMenuOpen()) ob(); };'
    '  }'
    '  function tryPatch(){'
    '    patchEl(document.querySelector(".monaco-editor .inputarea"));'
    '    patchEl(document.querySelector(".monaco-editor .native-edit-context"));'
    '    if(window.editor&&!window.editor._fp){'
    '      window.editor._fp=true;'
    '      var oe=window.editor.focus.bind(window.editor);'
    '      window.editor.focus=function(){ if(!isMenuOpen()) oe(); };'
    '    }'
    '  }'
    '  tryPatch();'
    '  var obs=new MutationObserver(tryPatch);'
    '  obs.observe(document.body,{childList:true,subtree:true});'
    '})()';

class ObjectSourcePage extends StatefulWidget {
  final String name;
  final String objectType; // PROCEDURE | FUNCTION | PACKAGE | VIEW | TYPE
  final String ambiente;

  /// When true, renders content without a Scaffold (for embedding in a float window).
  final bool embedded;

  /// Callback para cambiar el ambiente desde el AppBar (solo en modo tab).
  /// Si es null, el ambiente se muestra como badge estático (modo ventana separada).
  final ValueChanged<String>? onAmbienteChanged;

  const ObjectSourcePage({
    super.key,
    required this.name,
    required this.objectType,
    required this.ambiente,
    this.embedded = false,
    this.onAmbienteChanged,
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

  _ViewerCompileStatus _compileStatus = _ViewerCompileStatus.idle;
  bool _minimap = true;
  bool _wordWrap = false;
  double _fontSize = 14;
  bool _showProblems = false;
  bool _backendChecking = false;
  bool _showPackageNav = true;
  String? _activeSubprogram;
  List<PlSqlIssue> _specIssues = [];
  List<PlSqlIssue> _bodyIssues = [];
  List<PlSqlIssue> _specCompileIssues = [];
  List<PlSqlIssue> _bodyCompileIssues = [];
  List<({String name, String kind, int line})> _subprograms = [];
  List<({String name, String kind, int line})> _specSubprograms = [];
  final TextEditingController _navSearchCtrl = TextEditingController();

  // Grants/owner from table DDL response — used in backup dialog for TABLE type
  String? _tableDdlGrants;
  String _tableDdlOwner = '';
  String _tableDdlCreateTable = '';
  String? _tableDdlComments;

  @override
  void initState() {
    super.initState();
    final isTable = widget.objectType == 'TABLE';
    final sourceFuture = isTable
        ? SchemaService.instance
              .getTableDdl(widget.name, ambiente: widget.ambiente)
              .then((ddl) {
                _tableDdlGrants = ddl.grants?.isNotEmpty == true
                    ? ddl.grants
                    : null;
                _tableDdlOwner = ddl.owner;
                _tableDdlCreateTable = ddl.createTable;
                _tableDdlComments = ddl.comments?.isNotEmpty == true
                    ? ddl.comments
                    : null;
                final parts = [
                  ddl.createTable,
                  if (ddl.comments != null && ddl.comments!.isNotEmpty)
                    ddl.comments!,
                ];
                return (spec: parts.join('\n\n'), body: null as String?);
              })
        : SchemaService.instance.getObjectSource(
            widget.name,
            widget.objectType,
            ambiente: widget.ambiente,
          );
    sourceFuture
        .then((data) {
          if (!mounted) return;
          setState(() {
            _data = data;
            // Only PACKAGE has a meaningful spec/body split
            if (data.body != null && widget.objectType == 'PACKAGE') {
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
    _navSearchCtrl.dispose();
    super.dispose();
  }

  void _copyCurrentSource() {
    final text = (_tabCtrl?.index == 1 && _bodyText.isNotEmpty)
        ? _bodyText
        : _specText;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    AppToast.info(
      'Fuente copiado al portapapeles',
      duration: const Duration(seconds: 2),
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
    setState(() {
      _compileStatus = _ViewerCompileStatus.compiling;
      if (isBody) {
        _bodyCompileIssues = [];
      } else {
        _specCompileIssues = [];
      }
    });
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
      final compileIssues = errors
          .map(
            (e) => PlSqlIssue(
              line: e.line,
              col: e.position,
              endCol: e.position + 1,
              message: e.text,
              severity: e.attribute == 'ERROR'
                  ? fm.MarkerSeverity.error
                  : fm.MarkerSeverity.warning,
              source: 'Oracle',
            ),
          )
          .toList();
      if (mounted) {
        setState(() {
          if (isBody) {
            _bodyCompileIssues = compileIssues;
          } else {
            _specCompileIssues = compileIssues;
          }
          _compileStatus = errors.isEmpty
              ? _ViewerCompileStatus.ok
              : _ViewerCompileStatus.error;
          if (errors.isNotEmpty) _showProblems = true;
        });
        AppLog.instance.compilation(
          objectName: widget.name,
          objectType: widget.objectType,
          ambiente: widget.ambiente,
          part: widget.objectType == 'PACKAGE'
              ? (isBody ? 'BODY' : 'SPEC')
              : null,
          errors: errors,
        );
        if (errors.isEmpty) {
          AppToast.success('${widget.name} compilado exitosamente');
        } else {
          AppToast.error(
            '${widget.name}: ${errors.length} error(es) de compilación '
            '— ver consola',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _compileStatus = _ViewerCompileStatus.error);
        AppToast.error('Error: $e', source: 'Compilación');
      }
    }
  }

  void _triggerFind() {
    _specCtrl?.runJavaScript(
      'try{editor.getAction("actions.find").run();}catch(e){}',
    );
  }

  void _openSnippetsManager() {
    openSnippetsManager(context);
  }

  // Parses PROCEDURE/FUNCTION declarations with their 1-based line numbers.
  List<({String name, String kind, int line})> _parseSubprograms(String text) {
    final result = <({String name, String kind, int line})>[];
    final lines = text.split('\n');
    final re = RegExp(
      r'^\s*(PROCEDURE|FUNCTION)\s+(\w+)',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final m = re.firstMatch(lines[i]);
      if (m != null) {
        result.add((
          name: m.group(2)!,
          kind: m.group(1)!.toUpperCase(),
          line: i + 1,
        ));
      }
    }
    return result;
  }

  List<PlSqlIssue> get _allActiveIssues {
    final isBody = _tabCtrl?.index == 1;
    final syntax = isBody ? _bodyIssues : _specIssues;
    final compile = isBody ? _bodyCompileIssues : _specCompileIssues;
    return [...compile, ...syntax]..sort((a, b) => a.line.compareTo(b.line));
  }

  /// Maneja la navegación a la definición de un objeto Oracle desde los editores
  /// embebidos. Usa [SourceTabController] si está disponible en el árbol.
  void _handleGotoDefinition(String name, String objectType) {
    final stc = SourceTabController.maybeOf(context);
    if (stc != null) {
      stc.openTab(
        name: name,
        objectType: objectType,
        ambiente: widget.ambiente,
      );
    } else {
      AppToast.info(
        'Abrí "$name" desde el explorador de objetos del panel lateral.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasTabs = _tabCtrl != null;
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final typeIcon = kTypeIcons[widget.objectType] ?? Icons.code_rounded;

    if (widget.embedded) return _buildEmbedded(isDark, hasTabs);

    return Scaffold(
      appBar: _buildCompactHeader(isDark, hasTabs, typeColor, typeIcon),
      body: Column(
        children: [
          _buildViewToolbar(isDark),
          Expanded(
            child: Stack(
              children: [
                _buildBody(isDark),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _data == null ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: _data != null,
                      child: const StatusCard(message: 'Cargando fuente...'),
                    ),
                  ),
                ),
                // Overlay: abrirlo no debe redimensionar el editor.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildProblemsPanel(isDark),
                ),
              ],
            ),
          ),
          _buildStatusBar(isDark),
        ],
      ),
    );
  }

  /// Header compacto estilo VS Code: 40 px de alto, acento lateral con el color
  /// del tipo, fondo neutro que se adapta al tema. Sin colores saturados.
  PreferredSizeWidget _buildCompactHeader(
    bool isDark,
    bool hasTabs,
    Color typeColor,
    IconData typeIcon,
  ) {
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final nameColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1A1A1A);
    final ambColor = AmbienteSelector.colorForAmbiente(widget.ambiente);

    const rowH = 40.0;
    const borderH = 1.0;
    const tabH = 34.0;
    final totalH = hasTabs ? rowH + borderH + tabH : rowH + borderH;

    return PreferredSize(
      preferredSize: Size.fromHeight(totalH),
      child: Container(
        color: bg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Fila principal ─────────────────────────────────────────────
            SizedBox(
              height: rowH,
              child: Row(
                children: [
                  // Acento lateral: 3 px del color del tipo
                  Container(width: 3, color: typeColor),
                  const SizedBox(width: 10),

                  // Icono del tipo
                  Icon(typeIcon, size: 15, color: typeColor),
                  const SizedBox(width: 6),

                  // Badge del tipo (p.ej. "PAQUETE")
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: typeColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      _typeLabel(widget.objectType).toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        color: typeColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Nombre del objeto
                  Expanded(
                    child: Text(
                      widget.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: nameColor,
                      ),
                    ),
                  ),

                  // Botón copiar nombre
                  Tooltip(
                    message: 'Copiar nombre',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.name));
                        AppToast.success('Nombre copiado: ${widget.name}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: nameColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),

                  // Separador
                  Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: borderColor,
                  ),

                  // Ambiente: selector o badge según si hay callback
                  if (widget.onAmbienteChanged != null)
                    AmbienteSelector(
                      value: widget.ambiente,
                      onChanged: widget.onAmbienteChanged!,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ambColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: ambColor.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        widget.ambiente,
                        style: TextStyle(
                          fontSize: 11,
                          color: ambColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            // Separador inferior de la fila principal
            Container(height: 1, color: borderColor),

            // ── TabBar (solo PACKAGE / TYPE) ────────────────────────────────
            if (hasTabs)
              SizedBox(
                height: tabH - 1,
                child: TabBar(
                  controller: _tabCtrl,
                  tabs: [
                    _TabWithBadge('Especificación', errorCount: _specErrors),
                    _TabWithBadge('Cuerpo', errorCount: _bodyErrors),
                  ],
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  indicatorColor: typeColor,
                  indicatorWeight: 2,
                  labelColor: typeColor,
                  unselectedLabelColor: isDark
                      ? Colors.white38
                      : Colors.black38,
                  dividerColor: Colors.transparent,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Embedded layout (no Scaffold) — used by the floating source window.
  Widget _buildEmbedded(bool isDark, bool hasTabs) {
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    return Column(
      children: [
        // Header with tabs and action buttons
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              if (hasTabs)
                Expanded(
                  child: TabBar(
                    controller: _tabCtrl,
                    tabs: [
                      _TabWithBadge(
                        'Especificación',
                        errorCount: _specErrors,
                        compact: true,
                      ),
                      _TabWithBadge(
                        'Cuerpo',
                        errorCount: _bodyErrors,
                        compact: true,
                      ),
                    ],
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    indicatorColor: typeColor,
                    labelColor: typeColor,
                    unselectedLabelColor: isDark
                        ? Colors.white54
                        : Colors.black54,
                    indicatorSize: TabBarIndicatorSize.label,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                )
              else
                const Spacer(),
              if (_data != null) ...[
                IconButton(
                  tooltip: 'Copiar fuente',
                  icon: const Icon(Icons.content_copy_outlined, size: 16),
                  onPressed: _copyCurrentSource,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  tooltip: 'Generar backup SQL',
                  icon: const Icon(Icons.download_outlined, size: 16),
                  onPressed: _showBackupDialog,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  tooltip: 'Buscar (Ctrl+F)',
                  icon: const Icon(Icons.search_rounded, size: 16),
                  onPressed: _triggerFind,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  tooltip: 'Snippets de usuario',
                  icon: const Icon(Icons.code_rounded, size: 16),
                  onPressed: _openSnippetsManager,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                _buildCompileBtn(compact: true),
              ],
            ],
          ),
        ),
        _buildViewToolbar(isDark),
        Expanded(
          child: Stack(
            children: [
              _buildBody(isDark),
              Positioned(
                left: 12,
                bottom: 12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _data == null ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: _data != null,
                    child: const StatusCard(message: 'Cargando fuente...'),
                  ),
                ),
              ),
              // Overlay: abrirlo no debe redimensionar el editor.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildProblemsPanel(isDark),
              ),
            ],
          ),
        ),
        _buildStatusBar(isDark),
      ],
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
      final editor = _MultiDocSourceEditor(
        spec: _data!.spec,
        body: _data!.body,
        isDark: isDark,
        ambiente: widget.ambiente,
        isPlSql: widget.objectType != 'VIEW' && widget.objectType != 'TABLE',
        objectType: widget.objectType,
        tabCtrl: _tabCtrl!,
        minimap: _minimap,
        wordWrap: _wordWrap,
        fontSize: _fontSize,
        onControllerReady: (c) => setState(() {
          _specCtrl = c;
          _specText = _data!.spec;
          _bodyText = _data!.body ?? '';
          _subprograms = _parseSubprograms(_data!.body ?? '');
          _specSubprograms = _parseSubprograms(_data!.spec);
        }),
        onSpecTextChanged: (t) {
          _specText = t;
          _specSubprograms = _parseSubprograms(t);
        },
        onBodyTextChanged: (t) {
          _bodyText = t;
          final parsed = _parseSubprograms(t);
          if (parsed.length != _subprograms.length) {
            setState(() => _subprograms = parsed);
          } else {
            _subprograms = parsed;
          }
        },
        onSpecErrorsChanged: (n) => setState(() => _specErrors = n),
        onBodyErrorsChanged: (n) => setState(() => _bodyErrors = n),
        onSpecIssuesChanged: (issues) => setState(() => _specIssues = issues),
        onBodyIssuesChanged: (issues) => setState(() => _bodyIssues = issues),
        onBackendChecking: (v) => setState(() => _backendChecking = v),
        onGotoDefinition: _handleGotoDefinition,
      );
      final showNav = _showPackageNav && _subprograms.isNotEmpty;
      return Row(
        children: [
          if (showNav) _buildPackageNav(isDark),
          Expanded(child: editor),
        ],
      );
    }

    return _MonacoSourceTab(
      // For non-PACKAGE types, use body if spec is empty (some servers return body only)
      source: _data!.spec.isNotEmpty ? _data!.spec : (_data!.body ?? ''),
      isDark: isDark,
      ambiente: widget.ambiente,
      isPlSql: widget.objectType != 'VIEW' && widget.objectType != 'TABLE',
      minimap: _minimap,
      wordWrap: _wordWrap,
      fontSize: _fontSize,
      onControllerReady: (c) => setState(() {
        _specCtrl = c;
        _specText = _data!.spec;
      }),
      onTextChanged: (t) => _specText = t,
      onErrorCountChanged: (n) => setState(() => _specErrors = n),
      onIssuesChanged: (issues) => setState(() => _specIssues = issues),
      onBackendChecking: (v) => setState(() => _backendChecking = v),
      onGotoDefinition: _handleGotoDefinition,
    );
  }

  Widget _buildViewToolbar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final issues = _allActiveIssues;
    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    final warnCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.warning)
        .length;
    final isPackage =
        widget.objectType == 'PACKAGE' || widget.objectType == 'TYPE';
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          // ── Vista ──────────────────────────────────────────────────────────
          if (isPackage)
            _ViewerToggleBtn(
              icon: Icons.account_tree_outlined,
              tooltip: 'Navegador de subprogramas',
              active: _showPackageNav,
              onPressed: () =>
                  setState(() => _showPackageNav = !_showPackageNav),
            ),
          _ViewerToggleBtn(
            icon: Icons.map_outlined,
            tooltip: 'Minimap',
            active: _minimap,
            onPressed: () {
              setState(() => _minimap = !_minimap);
              _specCtrl?.runJavaScript(
                'try{window.flutterMonaco.updateOptions({minimap:{enabled:$_minimap}});}catch(e){}',
              );
            },
          ),
          _ViewerToggleBtn(
            icon: Icons.wrap_text_rounded,
            tooltip: 'Ajustar líneas',
            active: _wordWrap,
            onPressed: () {
              setState(() => _wordWrap = !_wordWrap);
              final v = _wordWrap ? 'on' : 'off';
              _specCtrl?.runJavaScript(
                'try{window.flutterMonaco.updateOptions({wordWrap:"$v"});}catch(e){}',
              );
            },
          ),
          const SizedBox(width: 4),
          _buildFontSizePill(cs),
          const SizedBox(width: 4),
          SizedBox(
            height: 16,
            child: VerticalDivider(color: cs.outlineVariant, width: 10),
          ),
          // ── Acciones ───────────────────────────────────────────────────────
          _ViewerIconBtn(
            icon: Icons.search_rounded,
            tooltip: 'Buscar (Ctrl+F)',
            onPressed: _triggerFind,
          ),
          if (_data != null) ...[
            _ViewerIconBtn(
              icon: Icons.content_copy_outlined,
              tooltip: 'Copiar fuente',
              onPressed: _copyCurrentSource,
            ),
            _ViewerIconBtn(
              icon: Icons.download_outlined,
              tooltip: 'Generar backup SQL',
              onPressed: _showBackupDialog,
            ),
            _ViewerIconBtn(
              icon: Icons.code_rounded,
              tooltip: 'Snippets de usuario',
              onPressed: _openSnippetsManager,
            ),
            SizedBox(
              height: 16,
              child: VerticalDivider(color: cs.outlineVariant, width: 10),
            ),
          ],
          const Spacer(),
          // ── Errores + Compilar ─────────────────────────────────────────────
          if (_backendChecking)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (errCount > 0 || warnCount > 0)
            Tooltip(
              message: _showProblems
                  ? 'Ocultar problemas'
                  : 'Mostrar problemas',
              waitDuration: const Duration(milliseconds: 400),
              child: GestureDetector(
                onTap: () => setState(() => _showProblems = !_showProblems),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: errCount > 0
                        ? Colors.red.shade400.withValues(alpha: 0.12)
                        : Colors.orange.shade400.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: errCount > 0
                          ? Colors.red.shade400.withValues(alpha: 0.4)
                          : Colors.orange.shade400.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (errCount > 0) ...[
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$errCount',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ],
                      if (errCount > 0 && warnCount > 0)
                        const SizedBox(width: 6),
                      if (warnCount > 0) ...[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: Colors.orange.shade400,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$warnCount',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (_data != null) _buildCompileBtn(),
        ],
      ),
    );
  }

  Widget _buildFontSizePill(ColorScheme cs) {
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.7),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _fontSize > 10
                ? () {
                    setState(() => _fontSize = (_fontSize - 2).clamp(10, 28));
                    _specCtrl?.runJavaScript(
                      'try{window.flutterMonaco.updateOptions({fontSize:${_fontSize.toInt()}});}catch(e){}',
                    );
                  }
                : null,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(11),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Icon(
                Icons.remove,
                size: 12,
                color: _fontSize > 10
                    ? cs.onSurfaceVariant
                    : cs.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          Text(
            '${_fontSize.toInt()}',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          InkWell(
            onTap: _fontSize < 28
                ? () {
                    setState(() => _fontSize = (_fontSize + 2).clamp(10, 28));
                    _specCtrl?.runJavaScript(
                      'try{window.flutterMonaco.updateOptions({fontSize:${_fontSize.toInt()}});}catch(e){}',
                    );
                  }
                : null,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(11),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Icon(
                Icons.add,
                size: 12,
                color: _fontSize < 28
                    ? cs.onSurfaceVariant
                    : cs.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompileBtn({bool compact = false}) {
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final size = compact ? 18.0 : 22.0;
    return switch (_compileStatus) {
      _ViewerCompileStatus.idle when !compact => GestureDetector(
        onTap: _compile,
        child: Tooltip(
          message: 'Compilar (F5)',
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: typeColor.withValues(alpha: 0.35),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: 14, color: typeColor),
                const SizedBox(width: 4),
                Text(
                  'Compilar',
                  style: TextStyle(
                    fontSize: 11,
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _ViewerCompileStatus.idle => IconButton(
        tooltip: 'Compilar',
        icon: Icon(Icons.play_arrow_rounded, size: size, color: typeColor),
        onPressed: _compile,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      _ViewerCompileStatus.compiling => Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
        child: SizedBox(
          width: compact ? 14 : 18,
          height: compact ? 14 : 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: compact ? typeColor : typeColor,
          ),
        ),
      ),
      _ViewerCompileStatus.ok =>
        compact
            ? IconButton(
                tooltip: 'Compilado — compilar de nuevo',
                icon: Icon(
                  Icons.check_circle_outline,
                  size: size,
                  color: const Color(0xFF4CAF50),
                ),
                onPressed: _compile,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            : GestureDetector(
                onTap: _compile,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: Color(0xFF4CAF50),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Compilado',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      _ViewerCompileStatus.error =>
        compact
            ? IconButton(
                tooltip: 'Compilación falló — compilar de nuevo',
                icon: Icon(
                  Icons.error_outline,
                  size: size,
                  color: Colors.orange,
                ),
                onPressed: _compile,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            : GestureDetector(
                onTap: _compile,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: Colors.orange),
                      SizedBox(width: 4),
                      Text(
                        'Error — reintentar',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    };
  }

  Widget _buildStatusBar(bool isDark) {
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark
            ? typeColor.withValues(alpha: 0.1)
            : typeColor.withValues(alpha: 0.06),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _typeLabel(widget.objectType).toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                color: typeColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.name,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const Spacer(),
          Text(
            widget.ambiente,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'PL/SQL',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
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
