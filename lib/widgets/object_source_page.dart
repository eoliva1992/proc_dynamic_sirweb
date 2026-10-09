import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;
import '../models/bulk_backup_item.dart';
import '../services/app_log.dart';
import '../services/backup_service.dart';
import '../services/batch_transfer_service.dart'
    show deployOpenSchemaObjectSource;
import '../services/bulk_backup_service.dart';
import '../services/schema_service.dart';
import '../screens/schema_object_diff_page.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import '_editor_themes.dart';
import 'ambiente_selector.dart';
import 'app_toast.dart';
import 'floating_window.dart' show showFloatingDialog;
import 'code_editor_panel.dart'
    show
        showInfoEventoWindow,
        showInfoDatoWindow,
        showAutorizacionesWindow,
        showEjecutarLlamadaWindow;
import 'constellation_background.dart';
import 'monaco_snippets.dart';
import 'plsql_tables.dart' show extractSqlTables;
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

const _kTiposInvocables = {'PROCEDURE', 'FUNCTION', 'PACKAGE'};

enum _ViewerCompileStatus { idle, compiling, ok, error }

enum _TransferStepStatus { pending, running, success, error }

/// Un paso visible en el panel de progreso de la transferencia (respaldo,
/// compilación en origen o despliegue a un destino puntual).
class _TransferStep {
  _TransferStep(this.label);
  final String label;
  _TransferStepStatus status = _TransferStepStatus.pending;
  String? detail;
}

enum _CtxMenuAction {
  gotoDef,
  infoEvento,
  infoDato,
  ejecutarLlamada,
  cut,
  copy,
  paste,
}

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
// ─── Guardia de foco y buscador para WebView2 en Windows ────────────────────────
// 1. Evita que window.flutterMonaco.forceFocus redirija el foco al código si el
//    usuario está interactuando con un input auxiliar (ej. cuadro de búsqueda).
// 2. Limpia el flag de búsqueda al hacer clic fuera del find-widget.
// 3. Define window.__fmOpenFind() para abrir el buscador y enfocar el input sin atrapar el foco.
// 4. Intercepta Ctrl+F para abrir el buscador de forma fiable.
const String _kFindAndFocusGuardJs =
    '(function(){'
    '  window.__fmFindWanted = false;'
    '  window.__fmContextMenuAux = null;'
    '  function isAuxFocused(){'
    '    var act = document.activeElement;'
    '    if(act && (act.tagName==="INPUT" || act.tagName==="TEXTAREA")) {'
    '      if(!act.classList.contains("inputarea") && !act.classList.contains("native-edit-context")) return true;'
    '    }'
    '    return false;'
    '  }'
    '  window.__fmAuxInput = function(){'
    '    if (window.__fmContextMenuAux) return window.__fmContextMenuAux;'
    '    var act = document.activeElement;'
    '    if(act && (act.tagName==="INPUT" || act.tagName==="TEXTAREA")) {'
    '      if(!act.classList.contains("inputarea") && !act.classList.contains("native-edit-context")) return act;'
    '    }'
    '    return null;'
    '  };'
    '  function shouldSuppressForceFocus(){'
    '    return window.__fmFindWanted || isAuxFocused();'
    '  }'
    '  function patchFn(obj, name){'
    '    if(!obj || !obj[name] || obj[name]._fp) return;'
    '    var orig = obj[name].bind(obj);'
    '    var patched = function(){'
    '      if(!shouldSuppressForceFocus()) return orig.apply(this, arguments);'
    '    };'
    '    patched._fp = true;'
    '    obj[name] = patched;'
    '  }'
    '  if(window.flutterMonaco){'
    '    patchFn(window.flutterMonaco, "forceFocus");'
    '    patchFn(window.flutterMonaco, "focus");'
    '    window.flutterMonaco.__fp = true;'
    '  }'
    '  function tryPatch(){'
    '    if(window.flutterMonaco && !window.flutterMonaco.__fp){'
    '      patchFn(window.flutterMonaco, "forceFocus");'
    '      patchFn(window.flutterMonaco, "focus");'
    '      window.flutterMonaco.__fp = true;'
    '    }'
    '  }'
    '  tryPatch();'
    '  var obs=new MutationObserver(tryPatch);'
    '  obs.observe(document.body,{childList:true,subtree:true});'
    '  document.addEventListener("mousedown",function(e){'
    '    window.__fmContextMenuAux = null;'
    '    var fw = document.querySelector(".find-widget");'
    '    if(!fw || !fw.contains(e.target)) {'
    '      window.__fmFindWanted = false;'
    '    }'
    '  },true);'
    '  window.__fmOpenFind = function(initialVal, targetLine){'
    '    window.__fmFindWanted = true;'
    '    try {'
    '      var ed = window.editor;'
    '      var fc = ed && ed.getContribution("editor.contrib.findController");'
    '      if(targetLine && ed){'
    '        ed.setPosition({lineNumber: targetLine, column: 1});'
    '        ed.revealLineInCenter(targetLine);'
    '      }'
    '      if(initialVal) {'
    '        if(fc && fc.getState()){ fc.getState().change({searchString: initialVal}, false); }'
    '      }'
    '      if(ed) { ed.trigger("keyboard", "actions.find"); }'
    '      if(initialVal && fc && fc.getState()){'
    '        fc.getState().change({searchString: initialVal}, false);'
    '      }'
    '      if(targetLine && ed){'
    '        ed.setPosition({lineNumber: targetLine, column: 1});'
    '        ed.revealLineInCenter(targetLine);'
    '      }'
    '    } catch(e){}'
    '    var count = 0;'
    '    var chase = setInterval(function(){'
    '      count++;'
    '      var inp = document.querySelector(".find-widget textarea, .find-widget input, .monaco-findInput textarea, .monaco-findInput input");'
    '      if(inp) {'
    '        if(initialVal !== undefined && initialVal !== null && initialVal !== "") {'
    '          if(inp.value !== initialVal) {'
    '            inp.value = initialVal;'
    '            inp.dispatchEvent(new Event("input", {bubbles: true}));'
    '            inp.dispatchEvent(new Event("change", {bubbles: true}));'
    '          }'
    '          try {'
    '            var fc2 = window.editor && window.editor.getContribution("editor.contrib.findController");'
    '            if(fc2 && fc2.getState()){ fc2.getState().change({searchString: initialVal}, false); }'
    '          } catch(_){}'
    '        }'
    '        inp.focus();'
    '        inp.select();'
    '        if(targetLine && window.editor){'
    '          try {'
    '            window.editor.setPosition({lineNumber: targetLine, column: 1});'
    '            window.editor.revealLineInCenter(targetLine);'
    '          } catch(_){}'
    '        }'
    '        if(document.activeElement === inp || count > 30) {'
    '          clearInterval(chase);'
    '          window.__fmFindWanted = false;'
    '        }'
    '      } else if(count > 30) {'
    '        clearInterval(chase);'
    '        window.__fmFindWanted = false;'
    '      }'
    '    }, 25);'
    '    if(targetLine){'
    '      setTimeout(function(){'
    '        try {'
    '          if(window.editor){'
    '            window.editor.setPosition({lineNumber: targetLine, column: 1});'
    '            window.editor.revealLineInCenter(targetLine);'
    '          }'
    '        } catch(_){}'
    '      }, 120);'
    '      setTimeout(function(){'
    '        try {'
    '          if(window.editor){'
    '            window.editor.setPosition({lineNumber: targetLine, column: 1});'
    '            window.editor.revealLineInCenter(targetLine);'
    '          }'
    '        } catch(_){}'
    '      }, 350);'
    '    }'
    '  };'
    '  document.addEventListener("keydown",function(e){'
    '    if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==="f"){'
    '      e.preventDefault();'
    '      window.__fmOpenFind();'
    '    }'
    '  },true);'
    '})()';

class ObjectSourcePage extends StatefulWidget {
  final String name;
  final String objectType; // PROCEDURE | FUNCTION | PACKAGE | VIEW | TYPE
  final String ambiente;

  /// When true, renders content without a Scaffold (for embedding in a float window).
  final bool embedded;

  /// Línea inicial a la que navegar y posicionar el cursor tras cargar el fuente.
  final int? initialLine;

  /// Término de búsqueda opcional para precargar en el widget Find de Monaco.
  final String? initialSearchTerm;

  /// Callback para cambiar el ambiente desde el AppBar (solo en modo tab).
  /// Si es null, el ambiente se muestra como badge estático (modo ventana separada).
  final ValueChanged<String>? onAmbienteChanged;

  /// Notifica si el fuente actual difiere del contenido cargado o compilado.
  final ValueChanged<bool>? onDirtyChanged;

  /// Fuente precargado opcional para pruebas o inicialización directa sin llamadas de red.
  final ({String spec, String? body})? initialData;

  const ObjectSourcePage({
    super.key,
    required this.name,
    required this.objectType,
    required this.ambiente,
    this.embedded = false,
    this.initialLine,
    this.initialSearchTerm,
    this.onAmbienteChanged,
    this.onDirtyChanged,
    this.initialData,
  });

  @override
  State<ObjectSourcePage> createState() => _ObjectSourcePageState();
}

class _ObjectSourcePageState extends State<ObjectSourcePage>
    with TickerProviderStateMixin {
  TabController? _tabCtrl;
  ({String spec, String? body})? _data;
  Object? _error;
  bool _loading = false;
  String? _objectStatus;
  bool _statusLoading = true;
  bool _initialLineNavigated = false;

  // single shared controller — multi-doc for packages/types, single-doc for others
  fm.MonacoController? _specCtrl;
  String _specText = '';
  String _bodyText = '';
  String _originalSpecText = '';
  String _originalBodyText = '';
  bool _isDirty = false;
  final List<({bool isBody, String text})> _undoStack = [];
  final List<({bool isBody, String text})> _redoStack = [];
  String? _pendingHistorySpecText;
  String? _pendingHistoryBodyText;
  int _specErrors = 0;
  int _bodyErrors = 0;
  bool _transferring = false;

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
    _loadObjectSource();
  }

  @override
  void didUpdateWidget(covariant ObjectSourcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        oldWidget.objectType != widget.objectType ||
        oldWidget.ambiente != widget.ambiente) {
      _loadObjectStatus();
    }
    if (oldWidget.initialLine != widget.initialLine ||
        oldWidget.initialSearchTerm != widget.initialSearchTerm ||
        oldWidget.name != widget.name) {
      _initialLineNavigated = false;
      if (_specCtrl != null) {
        _navigateToInitialLineIfNeeded(_specCtrl!);
      }
    }
  }

  Future<void> _loadObjectStatus() async {
    final requestedName = widget.name;
    final requestedType = widget.objectType;
    final requestedAmbiente = widget.ambiente;
    if (mounted) setState(() => _statusLoading = true);
    String? status;
    try {
      final info = await SchemaService.instance.getObjectInfo(
        requestedName,
        requestedType,
        ambiente: requestedAmbiente,
      );
      for (final property in info) {
        if (property.name.toUpperCase() == 'STATUS') {
          status = property.value.trim().toUpperCase();
          break;
        }
      }
    } catch (_) {}
    if (!mounted ||
        requestedName != widget.name ||
        requestedType != widget.objectType ||
        requestedAmbiente != widget.ambiente) {
      return;
    }
    setState(() {
      _objectStatus = status;
      _statusLoading = false;
    });
  }

  Future<void> _loadObjectSource() async {
    if (!await _confirmDiscardIfDirty()) return;
    _loadObjectStatus();
    final isTable = widget.objectType == 'TABLE';
    _tabCtrl?.dispose();
    _tabCtrl = null;
    _initialLineNavigated = false;
    _specText = '';
    _bodyText = '';
    _originalSpecText = '';
    _originalBodyText = '';
    _setDirty(false);
    _specErrors = 0;
    _bodyErrors = 0;
    _specIssues = [];
    _bodyIssues = [];
    _specCompileIssues = [];
    _bodyCompileIssues = [];
    _activeSubprogram = null;
    _compileStatus = _ViewerCompileStatus.idle;
    if (widget.initialData != null) {
      final data = widget.initialData!;
      _data = data;
      _setSourceBaseline(data);
      _loading = false;
      if (data.body != null &&
          (widget.objectType == 'PACKAGE' ||
              widget.objectType == 'PACKAGE BODY' ||
              widget.objectType == 'TYPE')) {
        final initialIndex =
            (widget.initialLine != null && data.body!.isNotEmpty) ? 1 : 0;
        _tabCtrl = TabController(
          length: 2,
          vsync: this,
          initialIndex: initialIndex,
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _data = null;
      });
    }
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
            _loading = false;
            _setSourceBaseline(data);
            // Only PACKAGE/TYPE/PACKAGE BODY has a meaningful spec/body split
            if (data.body != null &&
                (widget.objectType == 'PACKAGE' ||
                    widget.objectType == 'PACKAGE BODY' ||
                    widget.objectType == 'TYPE')) {
              final initialIndex =
                  (widget.initialLine != null && data.body!.isNotEmpty) ? 1 : 0;
              _tabCtrl = TabController(
                length: 2,
                vsync: this,
                initialIndex: initialIndex,
              );
            }
          });
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = e;
            });
          }
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

  bool get _sourceIsDirty =>
      _specText != _originalSpecText || _bodyText != _originalBodyText;

  String get _effectiveSpecSource =>
      _data!.spec.isNotEmpty ? _data!.spec : (_data!.body ?? '');

  void _setSourceBaseline(({String spec, String? body}) data) {
    _originalSpecText = data.spec.isNotEmpty ? data.spec : (data.body ?? '');
    _originalBodyText = data.body ?? '';
    _bodyText = _originalBodyText;
    _undoStack.clear();
    _redoStack.clear();
    _pendingHistorySpecText = null;
    _pendingHistoryBodyText = null;
    _setDirty(false);
  }

  void _refreshDirtyState() => _setDirty(_sourceIsDirty);

  void _setDirty(bool value) {
    if (_isDirty == value) return;
    _isDirty = value;
    widget.onDirtyChanged?.call(value);
  }

  Future<bool> _confirmDiscardIfDirty({String action = 'continuar'}) async {
    if (!_isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: const ConstellationDialogTitle(
          child: Text('Cambios sin guardar'),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('¿Descartar los cambios para $action?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true) {
      _setDirty(false);
      return true;
    }
    return false;
  }

  Future<void> _refreshObjectSource() async {
    await _loadObjectSource();
  }

  Future<void> _changeAmbiente(String ambiente) async {
    if (!await _confirmDiscardIfDirty(action: 'cambiar el ambiente')) return;
    widget.onAmbienteChanged?.call(ambiente);
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
          if (errors.isEmpty) {
            if (isBody) {
              _originalBodyText = text;
            } else {
              _originalSpecText = text;
            }
            _refreshDirtyState();
          }
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
      'try{window.__fmOpenFind ? window.__fmOpenFind() : (window.editor && window.editor.getAction("actions.find").run());}catch(e){}',
    );
  }

  void _recordSourceText(String text, {required bool isBody}) {
    if (!mounted) return;
    final pendingText = isBody
        ? _pendingHistoryBodyText
        : _pendingHistorySpecText;
    if (pendingText == text) {
      if (isBody) {
        _pendingHistoryBodyText = null;
      } else {
        _pendingHistorySpecText = null;
      }
      return;
    }

    final previous = isBody ? _bodyText : _specText;
    if (text == previous) return;
    final hadUndo = _undoStack.isNotEmpty;
    final hadRedo = _redoStack.isNotEmpty;
    final wasDirty = _isDirty;
    _undoStack.add((isBody: isBody, text: previous));
    if (_undoStack.length > 200) _undoStack.removeAt(0);
    _redoStack.clear();

    _refreshDirtyState();
    var navigationChanged = false;
    if (isBody) {
      _bodyText = text;
      final parsed = _parseSubprograms(text);
      navigationChanged =
          parsed.length != _subprograms.length ||
          Iterable<int>.generate(
            parsed.length,
          ).any((i) => parsed[i] != _subprograms[i]);
      if (navigationChanged) _subprograms = parsed;
    } else {
      _specText = text;
      if (_tabCtrl != null) {
        final parsed = _parseSubprograms(text);
        navigationChanged =
            parsed.length != _specSubprograms.length ||
            Iterable<int>.generate(
              parsed.length,
            ).any((i) => parsed[i] != _specSubprograms[i]);
        if (navigationChanged) _specSubprograms = parsed;
      }
    }
    if (hadUndo != _undoStack.isNotEmpty ||
        hadRedo != _redoStack.isNotEmpty ||
        wasDirty != _isDirty ||
        navigationChanged) {
      setState(() {});
    }
  }

  Future<void> _applyHistoryEntry(
    ({bool isBody, String text}) entry, {
    required bool toRedo,
  }) async {
    final ctrl = _specCtrl;
    if (ctrl == null) return;

    final current = entry.isBody ? _bodyText : _specText;
    final currentEntry = (isBody: entry.isBody, text: current);
    if (toRedo) {
      _redoStack.add(currentEntry);
    } else {
      _undoStack.add(currentEntry);
    }
    if (entry.isBody) {
      _bodyText = entry.text;
      _pendingHistoryBodyText = entry.text;
    } else {
      _specText = entry.text;
      _pendingHistorySpecText = entry.text;
    }
    setState(() {
      _refreshDirtyState();
      if (entry.isBody) {
        _subprograms = _parseSubprograms(entry.text);
      } else if (_tabCtrl != null) {
        _specSubprograms = _parseSubprograms(entry.text);
      }
    });

    final document = entry.isBody && _tabCtrl != null
        ? ctrl.documentByUri(Uri.parse('file:///source/body.sql'))
        : _tabCtrl != null
        ? ctrl.documentByUri(Uri.parse('file:///source/spec.sql'))
        : ctrl.document;
    await document.setText(entry.text);
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    await _applyHistoryEntry(entry, toRedo: true);
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    await _applyHistoryEntry(entry, toRedo: false);
  }

  void _openSnippetsManager() {
    openSnippetsManager(context);
  }

  void _navigateToInitialLineIfNeeded(fm.MonacoController ctrl) {
    final line = widget.initialLine;
    final searchTerm = widget.initialSearchTerm?.trim();
    if ((line == null || line <= 0) &&
        (searchTerm == null || searchTerm.isEmpty)) {
      return;
    }
    if (_initialLineNavigated) return;
    _initialLineNavigated = true;

    void doNavigate() {
      if (!mounted) return;
      if (line != null && line > 0) {
        ctrl.setCursorPosition(fm.Position(line: line, column: 1));
        ctrl.revealLine(line, center: true);
        ctrl.runJavaScript(
          'try{'
          'var ed = window.editor;'
          'if(ed){'
          '  ed.setPosition({lineNumber:$line,column:1});'
          '  ed.revealLineInCenter($line);'
          '  ed.focus();'
          '}'
          '}catch(e){}',
        );
      }

      if (searchTerm != null && searchTerm.isNotEmpty) {
        final escaped = jsonEncode(searchTerm);
        final lineArg = line != null && line > 0 ? '$line' : 'null';
        // Pre-cargar el término de búsqueda en el widget Find de Monaco y enfocarlo con auto-focus
        ctrl.runJavaScript(
          'try{'
          'var term=$escaped;'
          'if(window.__fmOpenFind){'
          '  window.__fmOpenFind(term, $lineArg);'
          '} else {'
          '  var ed=window.editor;'
          '  var fc=ed && ed.getContribution("editor.contrib.findController");'
          '  if(fc && fc.getState()){ fc.getState().change({searchString: term}, false); }'
          '  if(ed) {'
          '    ed.getAction("actions.find").run();'
          '    if($lineArg){ ed.setPosition({lineNumber:$lineArg,column:1}); ed.revealLineInCenter($lineArg); }'
          '  }'
          '}'
          '}catch(e){}',
        );
      }
    }

    Future.delayed(const Duration(milliseconds: 150), doNavigate);
    Future.delayed(const Duration(milliseconds: 400), doNavigate);
  }

  void _openDiff() {
    showSchemaObjectDiff(
      context,
      objectName: widget.name,
      objectType: widget.objectType,
      sourceAmbiente: widget.ambiente,
    );
  }

  // ── Transferencia a otro ambiente ───────────────────────────────────────────

  /// Compila en el ambiente actual únicamente las partes (SPEC/BODY) que
  /// tengan cambios sin guardar; si no hay cambios, no hace nada. Cancela la
  /// transferencia (devuelve `false`) ante cualquier error de compilación.
  Future<bool> _compileForTransfer() async {
    final specChanged = _specText != _originalSpecText;
    final bodyChanged = _tabCtrl != null && _bodyText != _originalBodyText;
    if (!specChanged && !bodyChanged) return true;

    Future<bool> compilePart(String text, {required bool isBody}) async {
      final objType = (isBody && widget.objectType == 'PACKAGE')
          ? 'PACKAGE BODY'
          : widget.objectType;
      try {
        final errors = await SchemaService.instance.compileObject(
          text,
          widget.name,
          objType,
          ambiente: widget.ambiente,
        );
        AppLog.instance.compilation(
          objectName: widget.name,
          objectType: widget.objectType,
          ambiente: widget.ambiente,
          part: widget.objectType == 'PACKAGE'
              ? (isBody ? 'BODY' : 'SPEC')
              : null,
          errors: errors,
          source: 'Transferencia',
        );
        if (errors.isNotEmpty) {
          AppToast.error(
            '${widget.name}: error de compilación en ${widget.ambiente} '
            '— transferencia cancelada',
            source: 'Transferencia',
          );
          return false;
        }
        if (isBody) {
          _originalBodyText = text;
        } else {
          _originalSpecText = text;
        }
        return true;
      } catch (e) {
        AppToast.error(
          'Error al compilar en ${widget.ambiente}: $e',
          source: 'Transferencia',
        );
        return false;
      }
    }

    if (specChanged && !await compilePart(_specText, isBody: false)) {
      return false;
    }
    if (bodyChanged && !await compilePart(_bodyText, isBody: true)) {
      return false;
    }
    if (mounted) _refreshDirtyState();
    return true;
  }

  /// Busca si ya existe un objeto con el mismo nombre/tipo en [ambiente],
  /// usando la metadata de schema en caché (puede refrescarse en background).
  /// Si la verificación falla, se asume que no existe para no bloquear al
  /// usuario — la confirmación de reemplazo es solo una ayuda, no una regla.
  Future<bool> _objectExistsIn(String ambiente) async {
    try {
      final metadata = await SchemaService.instance.getMetadata(
        ambiente: ambiente,
      );
      final upperName = widget.name.toUpperCase();
      if (widget.objectType == 'VIEW') {
        return metadata.views.contains(upperName);
      }
      return metadata.objects.any(
        (o) => o.name == upperName && o.type == widget.objectType,
      );
    } catch (_) {
      return false;
    }
  }

  Future<({Set<String> destinos, bool backup})?> _pickTransferTarget(
    List<String> destinos,
  ) {
    final selected = <String>{destinos.first};
    var backup = false;
    return showFloatingDialog<({Set<String> destinos, bool backup})>(
      context,
      (ctx, close) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          title: const ConstellationDialogTitle(
            child: Text('Transferir a otro ambiente'),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se transferirá "${widget.name}" (${widget.objectType}) '
                  'desde ${widget.ambiente} a los ambientes elegidos.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                for (final a in destinos)
                  InkWell(
                    onTap: () => setDlg(() {
                      if (selected.contains(a)) {
                        selected.remove(a);
                      } else {
                        selected.add(a);
                      }
                    }),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: selected.contains(a),
                              onChanged: (v) => setDlg(() {
                                if (v ?? false) {
                                  selected.add(a);
                                } else {
                                  selected.remove(a);
                                }
                              }),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            AmbienteSelector.iconForAmbiente(a),
                            size: 16,
                            color: AmbienteSelector.colorForAmbiente(a),
                          ),
                          const SizedBox(width: 8),
                          Text(a),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 20),
                InkWell(
                  onTap: () => setDlg(() => backup = !backup),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: backup,
                            onChanged: (v) => setDlg(() => backup = v ?? false),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Respaldar cada destino antes de transferir',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => close(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => close((destinos: Set.of(selected), backup: backup)),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmProdTransfer() {
    return showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: const ConstellationDialogTitle(
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Transferir a Producción'),
            ],
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Vas a transferir "${widget.name}" al ambiente de Producción.\n'
            'Esta acción puede afectar datos y procesos reales.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => close(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmReplaceInTargets(List<String> existentes) {
    return showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: const ConstellationDialogTitle(
          child: Text('El objeto ya existe'),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '"${widget.name}" ya existe en ${existentes.join(', ')}. '
            '¿Confirmás reemplazarlo con la versión actual?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => close(true),
            child: const Text('Reemplazar'),
          ),
        ],
      ),
    );
  }

  /// Respalda en disco el fuente que actualmente tiene cada ambiente en
  /// [destinos] (si existe) antes de sobrescribirlo, todos bajo una misma
  /// carpeta elegida una sola vez. Cancela toda la transferencia si el
  /// usuario descarta el selector de carpeta o si falla alguna escritura.
  Future<bool> _backupDestinationsBeforeTransfer(List<String> destinos) async {
    final porRespaldar = <String, ({String spec, String? body})>{};
    for (final destino in destinos) {
      try {
        final source = await SchemaService.instance.getObjectSource(
          widget.name,
          widget.objectType,
          ambiente: destino,
        );
        if (source.spec.isNotEmpty ||
            (source.body != null && source.body!.isNotEmpty)) {
          porRespaldar[destino] = source;
        }
      } catch (_) {
        // no existía en ese destino — nada que respaldar allí
      }
    }
    if (porRespaldar.isEmpty) return true;

    final basePath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Carpeta para los respaldos previos a la transferencia',
    );
    if (basePath == null) {
      AppToast.warning('Respaldo cancelado — transferencia abortada');
      return false;
    }

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final item = BulkBackupItem(
      name: widget.name,
      type: widget.objectType,
      source: BulkBackupSource.schema,
    );
    final fallos = <String>[];
    for (final entry in porRespaldar.entries) {
      final destino = entry.key;
      final source = entry.value;
      final safeTarget = destino.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetDir = Directory(
        '$basePath/PRE_TRANSFER_${safeTarget}_$stamp',
      );
      final script = BulkBackupService.buildSchemaScript(
        item: item,
        ambiente: destino,
        spec: source.spec,
        body: source.body,
      );
      final writeResult = await BulkBackupService.writeAll(
        directory: targetDir,
        ambiente: destino,
        items: [item],
        scripts: {item.id: script},
      );
      for (final fail in writeResult.failures) {
        fallos.add('$destino: ${fail.error}');
      }
    }

    if (fallos.isNotEmpty) {
      AppToast.error(
        'No se pudo respaldar ${fallos.join(' · ')} — transferencia abortada',
        source: 'Transferencia',
      );
      return false;
    }
    AppToast.success(
      'Respaldo generado para ${porRespaldar.keys.join(', ')}',
      source: 'Transferencia',
    );
    return true;
  }

  Future<void> _transferToAmbiente() async {
    if (_transferring || _data == null || widget.objectType == 'TABLE') return;
    final destinos = AmbienteSelector.ambientes
        .where((a) => a != widget.ambiente)
        .toList();
    if (destinos.isEmpty) return;

    final choice = await _pickTransferTarget(destinos);
    if (choice == null || choice.destinos.isEmpty || !mounted) return;
    final seleccionados = choice.destinos.toList();

    if (seleccionados.contains('Prod')) {
      final confirmed = await _confirmProdTransfer();
      if (confirmed != true || !mounted) return;
    }

    final existentes = <String>[];
    for (final destino in seleccionados) {
      if (await _objectExistsIn(destino)) existentes.add(destino);
    }
    if (!mounted) return;
    if (existentes.isNotEmpty) {
      final replace = await _confirmReplaceInTargets(existentes);
      if (replace != true || !mounted) return;
    }

    setState(() => _transferring = true);

    // Panel de progreso: muestra en vivo cuándo termina el respaldo y cada
    // despliegue, en vez de depender únicamente del toast final.
    _TransferStep? backupStep;
    final steps = <_TransferStep>[];
    if (choice.backup) {
      backupStep = _TransferStep('Respaldo de destino(s)');
      steps.add(backupStep);
    }
    final compileStep = _TransferStep('Compilación en origen');
    steps.add(compileStep);
    final deploySteps = <String, _TransferStep>{
      for (final d in seleccionados) d: _TransferStep('Transferir a $d'),
    };
    steps.addAll(deploySteps.values);

    final progress = ValueNotifier<List<_TransferStep>>(List.of(steps));
    void tick() {
      if (mounted) progress.value = List.of(steps);
    }

    void Function()? closeProgress;
    showFloatingDialog<void>(context, (ctx, close) {
      closeProgress = close;
      return ValueListenableBuilder<List<_TransferStep>>(
        valueListenable: progress,
        builder: (ctx, list, _) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          title: ConstellationDialogTitle(
            child: Text('Transfiriendo "${widget.name}"'),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final step in list) _buildTransferStepRow(step)],
            ),
          ),
        ),
      );
    }, barrierDismissible: false);

    Future<bool> runStep(
      _TransferStep step,
      Future<bool> Function() action,
    ) async {
      step.status = _TransferStepStatus.running;
      tick();
      bool ok;
      try {
        ok = await action();
      } catch (e) {
        ok = false;
        step.detail = '$e';
      }
      step.status = ok
          ? _TransferStepStatus.success
          : _TransferStepStatus.error;
      tick();
      return ok;
    }

    try {
      var aborted = false;
      if (backupStep != null) {
        final ok = await runStep(
          backupStep,
          () => _backupDestinationsBeforeTransfer(seleccionados),
        );
        if (!ok) aborted = true;
      }
      if (!aborted) {
        final ok = await runStep(compileStep, _compileForTransfer);
        if (!ok) aborted = true;
      }

      var exitosos = 0;
      final errores = <String>[];
      if (!aborted) {
        for (final destino in seleccionados) {
          final step = deploySteps[destino]!;
          final ok = await runStep(step, () async {
            final outcome = await deployOpenSchemaObjectSource(
              name: widget.name,
              objectType: widget.objectType,
              spec: _specText,
              body: _tabCtrl != null ? _bodyText : null,
              targetAmbiente: destino,
            );
            if (!outcome.success) step.detail = outcome.message;
            return outcome.success;
          });
          if (ok) {
            exitosos++;
          } else {
            errores.add('$destino: ${step.detail ?? 'error desconocido'}');
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || aborted) return;
      if (errores.isEmpty) {
        AppToast.success(
          '${widget.name} transferido a ${seleccionados.join(', ')}',
          source: 'Transferencia',
        );
      } else if (exitosos == 0) {
        AppToast.error(
          '${widget.name}: ${errores.join(' · ')}',
          source: 'Transferencia',
        );
      } else {
        AppToast.warning(
          '${widget.name}: $exitosos exitoso(s), ${errores.join(' · ')}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('Error al transferir: $e', source: 'Transferencia');
      }
    } finally {
      closeProgress?.call();
      if (mounted) setState(() => _transferring = false);
    }
  }

  Widget _buildTransferStepRow(_TransferStep step) {
    Widget leading;
    switch (step.status) {
      case _TransferStepStatus.pending:
        leading = Icon(
          Icons.radio_button_unchecked,
          size: 16,
          color: Colors.grey.shade500,
        );
        break;
      case _TransferStepStatus.running:
        leading = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case _TransferStepStatus.success:
        leading = const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Colors.green,
        );
        break;
      case _TransferStepStatus.error:
        leading = const Icon(Icons.error_rounded, size: 16, color: Colors.red);
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, height: 16, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: const TextStyle(fontSize: 13)),
                if (step.detail != null &&
                    step.status == _TransferStepStatus.error)
                  Text(
                    step.detail!,
                    style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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

                  // Botón ejecutar (para PROCEDURE, FUNCTION, PACKAGE)
                  if (_kTiposInvocables.contains(
                    widget.objectType.toUpperCase(),
                  )) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Ejecutar objeto (Ctrl+Shift+E)',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          showEjecutarLlamadaWindow(
                            context,
                            ambiente: widget.ambiente,
                            objeto: widget.name,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 16,
                                color: typeColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Ejecutar',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: typeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

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
                      onChanged: _changeAmbiente,
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
                  const SizedBox(width: 4),
                  _buildObjectStatusChip(isDark),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Comparar entre ambientes',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _openDiff,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        child: Icon(
                          Icons.compare_arrows_rounded,
                          size: 17,
                          color: typeColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Refrescar objeto',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _loading ? null : _refreshObjectSource,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                size: 17,
                                color: typeColor,
                              ),
                      ),
                    ),
                  ),
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
                  tooltip: 'Refrescar objeto',
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  onPressed: _loading ? null : _refreshObjectSource,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
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
                  tooltip: 'Comparar entre ambientes',
                  icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                  onPressed: _openDiff,
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
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loading ? null : _refreshObjectSource,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
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
          _refreshDirtyState();
          _subprograms = _parseSubprograms(_data!.body ?? '');
          _specSubprograms = _parseSubprograms(_data!.spec);
          if (_tabCtrl?.index == 0) {
            _navigateToInitialLineIfNeeded(c);
          }
        }),
        onBodyReady: (c) {
          if (_tabCtrl?.index == 1) {
            _navigateToInitialLineIfNeeded(c);
          }
        },
        onSpecTextChanged: (t) {
          _recordSourceText(t, isBody: false);
        },
        onBodyTextChanged: (t) {
          _recordSourceText(t, isBody: true);
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
      source: _effectiveSpecSource,
      isDark: isDark,
      ambiente: widget.ambiente,
      isPlSql: widget.objectType != 'VIEW' && widget.objectType != 'TABLE',
      minimap: _minimap,
      wordWrap: _wordWrap,
      fontSize: _fontSize,
      onControllerReady: (c) => setState(() {
        _specCtrl = c;
        _specText = _effectiveSpecSource;
        _refreshDirtyState();
        _navigateToInitialLineIfNeeded(c);
      }),
      onTextChanged: (t) {
        _recordSourceText(t, isBody: false);
      },
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
            icon: Icons.undo_rounded,
            tooltip: 'Deshacer (Ctrl+Z)',
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          _ViewerIconBtn(
            icon: Icons.redo_rounded,
            tooltip: 'Rehacer (Ctrl+Y)',
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
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
            if (widget.objectType != 'TABLE')
              _ViewerIconBtn(
                icon: Icons.move_up_rounded,
                tooltip: _transferring
                    ? 'Transfiriendo…'
                    : 'Transferir a otro ambiente',
                onPressed: _transferring ? null : _transferToAmbiente,
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

  Widget _buildObjectStatusChip(bool isDark) {
    final status = _objectStatus;
    final color = status == 'VALID'
        ? Colors.green.shade600
        : status == 'INVALID'
        ? Colors.red.shade600
        : Colors.grey.shade500;
    final label = _statusLoading ? '...' : (status ?? '?');
    return Tooltip(
      message: 'Estado Oracle: ${status ?? 'no disponible'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _statusLoading
                  ? Icons.hourglass_empty
                  : status == 'VALID'
                  ? Icons.check_circle_outline
                  : status == 'INVALID'
                  ? Icons.error_outline
                  : Icons.help_outline,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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
