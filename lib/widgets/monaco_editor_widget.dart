import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

import '../providers/procedimientos_provider.dart';
import '../services/schema_service.dart';
import '../services/sql_statement_analyzer.dart' show splitStatements;
import '_editor_themes.dart';
import '_monaco_oracle_completions.dart';
import 'app_toast.dart';
import 'code_editor_panel.dart'
    show
        showInfoEventoWindow,
        showInfoDatoWindow,
        showAutorizacionesWindow,
        showEjecutarLlamadaWindow,
        showEjecutarProcedimientoWindow;
import 'source_float_window.dart';

// Cached per-ambiente so jsonEncode doesn't run on every editor open
final Map<String, String> _schemaPayloadCache = {};

// CSS inyectado en la página Monaco para estilizar las decoraciones propias
// (separador visual entre sentencias del script SQL).
const String _kEditorCustomCss = '''
.sql-stmt-separator {
  border-top: 1px dashed rgba(128, 128, 128, 0.35);
}
''';

// Guard contra robo de foco en Monaco/WebView2:
// 1. Evita que window.flutterMonaco.forceFocus redirija el foco al editor mientras el buscador
//    o un input auxiliar esté enfocado, pero permite que el editor reciba foco normalmente al hacer clic en él.
// 2. Define window.__fmAuxInput() para que cortar, copiar y pegar (Ctrl+C/X/V) operen sobre el
//    input de búsqueda cuando éste tiene foco en lugar de editar el documento de código.
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
    '  window.__fmOpenFind = function(){'
    '    window.__fmFindWanted = true;'
    '    try { window.editor.trigger("keyboard", "actions.find"); } catch(e){}'
    '    var count = 0;'
    '    var chase = setInterval(function(){'
    '      count++;'
    '      var inp = document.querySelector(".find-widget .find-part input");'
    '      if(inp) {'
    '        inp.focus();'
    '        if(document.activeElement === inp || count > 20) {'
    '          clearInterval(chase);'
    '          window.__fmFindWanted = false;'
    '        }'
    '      } else if(count > 20) {'
    '        clearInterval(chase);'
    '        window.__fmFindWanted = false;'
    '      }'
    '    }, 25);'
    '  };'
    '  document.addEventListener("keydown",function(e){'
    '    if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==="f"){'
    '      e.preventDefault();'
    '      window.__fmOpenFind();'
    '    }'
    '  },true);'
    '})()';

// ─── Acciones del menú contextual ────────────────────────────────────────────
enum _CtxMenuAction {
  executeCurrent,
  executeAll,
  find,
  gotoDef,
  infoEvento,
  infoDato,
  ejecutar,
  ejecutarLlamada,
  cut,
  copy,
  paste,
}

// ─── Modelo de error (lo que el panel pasa desde _SyntaxError) ───────────────
class MonacoError {
  final int line;
  final int col;
  final String message;

  const MonacoError({
    required this.line,
    required this.col,
    required this.message,
  });
}

// ─── Controlador ─────────────────────────────────────────────────────────────
// Encola comandos hasta que Monaco esté listo (onReady).
// Usa el prefijo `fm.` en todos los tipos de flutter_monaco para evitar
// conflictos de nombres con nuestras clases locales.

class MonacoEditorController {
  fm.MonacoController? _ctrl;
  bool _ready = false;
  bool _disposed = false;
  final List<Future<void> Function(fm.MonacoController)> _pending = [];

  fm.MonacoController? get rawController => _ctrl;

  void attach(fm.MonacoController ctrl) {
    _disposed = false;
    _ctrl = ctrl;
    _ready = true;
    for (final cmd in _pending) {
      unawaited(_runCommandSafely(ctrl, cmd));
    }
    _pending.clear();
  }

  void _enqueue(Future<void> Function(fm.MonacoController) cmd) {
    if (_disposed) return;
    final ctrl = _ctrl;
    if (_ready && ctrl != null) {
      unawaited(_runCommandSafely(ctrl, cmd));
    } else {
      _pending.add(cmd);
    }
  }

  Future<void> _runCommandSafely(
    fm.MonacoController ctrl,
    Future<void> Function(fm.MonacoController) cmd,
  ) async {
    try {
      await cmd(ctrl);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('MonacoDisposedError') ||
          msg.contains('MonacoController has been disposed')) {
        _ctrl = null;
        _ready = false;
      }
    }
  }

  /// Muestra squiggles rojos para cada error del checker Dart.
  void setErrors(List<MonacoError> errors) {
    _enqueue((ctrl) async {
      final markers = errors
          .map(
            (e) => fm.MarkerData.error(
              range: fm.Range(
                startLine: e.line,
                startColumn: e.col,
                endLine: e.line,
                endColumn: e.col + 1,
              ),
              message: e.message,
              source: 'Checker',
            ),
          )
          .toList();
      await ctrl.document.setMarkers(markers, owner: 'plsql-checker');
    });
  }

  /// Limpia todos los squiggles del checker.
  void clearErrors() {
    _enqueue(
      (ctrl) async => ctrl.document.clearMarkers(owner: 'plsql-checker'),
    );
  }

  // Decoraciones de línea reutilizadas para los separadores visuales entre
  // sentencias (ver `.sql-stmt-separator` en el CSS inyectado del editor).
  fm.MonacoDecorationSet? _stmtSeparators;

  /// Dibuja una línea sutil justo encima del inicio de cada sentencia en
  /// [startLines] (1-based), para facilitar la lectura de scripts largos.
  void updateStatementSeparators(List<int> startLines) {
    _enqueue((ctrl) async {
      _stmtSeparators ??= await ctrl.createDecorationSet();
      await _stmtSeparators!.set([
        for (final line in startLines)
          fm.DecorationOptions.line(
            range: fm.Range.lines(line, line),
            className: 'sql-stmt-separator',
          ),
      ]);
    });
  }

  /// Cambia el lenguaje de resaltado del editor.
  void setLanguage(String lang) {
    final ml = lang == 'javascript'
        ? fm.MonacoLanguage.javascript
        : fm.MonacoLanguage.sql;
    _enqueue((ctrl) async => ctrl.document.setLanguage(ml));
  }

  void insertTextAtCursor(String text) {
    _enqueue((ctrl) async {
      final pos = await ctrl.getCursorPosition();
      if (pos != null) await ctrl.document.insert(pos, text);
    });
  }

  void revealLine(int line) {
    _enqueue(
      (ctrl) async => ctrl.revealPosition(fm.Position(line: line, column: 1)),
    );
  }

  /// Devuelve el texto actualmente seleccionado en el editor, o `null` si no
  /// hay selección (o el editor aún no está listo).
  Future<String?> getSelectedText() async {
    final ctrl = _ctrl;
    if (ctrl == null) return null;
    try {
      return await ctrl.evaluateJavaScript<String>(
        r'(()=>{'
        r'  try {'
        r'    const s = window.editor.getSelection();'
        r'    if (!s || s.isEmpty()) return null;'
        r'    return window.editor.getModel().getValueInRange(s) || null;'
        r'  } catch(e) { return null; }'
        r'})()',
      );
    } catch (_) {
      return null;
    }
  }

  void clearContent() {
    _enqueue((ctrl) async => ctrl.document.setText(''));
  }

  void setTheme(fm.MonacoTheme theme) {
    _enqueue((ctrl) => ctrl.setTheme(theme));
  }

  /// Envía el schema Oracle al WebView para que Monaco lo use en el
  /// autocompletado. Usa [SchemaService.instance.getMetadata] (sin refrescar)
  /// y pasa tablas, vistas y objetos como JSON via postMessage.
  /// Las columnas se envían bajo demanda cuando el usuario escribe "TABLA.".
  Future<void> loadAndSendSchema({String ambiente = 'Desa'}) async {
    try {
      String? payload = _schemaPayloadCache[ambiente];
      if (payload == null) {
        final schema = await SchemaService.instance.getMetadata(
          ambiente: ambiente,
        );
        payload = jsonEncode({
          'action': 'setCompletionSchema',
          'tables': schema.tables,
          'views': schema.views,
          'objects': schema.objects
              .map((o) => {'name': o.name, 'type': o.type})
              .toList(),
        });
        _schemaPayloadCache[ambiente] = payload;
      }
      _enqueue((ctrl) async {
        await ctrl.runJavaScript('monacoReceiveMessage($payload)');
      });
    } catch (_) {}
  }

  /// Carga los subprogramas de [packageName] y los envía a Monaco.
  /// Se llama automáticamente cuando el usuario escribe "PACKAGE.".
  Future<void> sendPackageSubprogramsFor(
    String packageName, {
    String ambiente = 'Desa',
  }) async {
    try {
      final subs = await SchemaService.instance.getPackageSubprograms(
        packageName,
        ambiente: ambiente,
      );
      final payload = jsonEncode({
        'action': 'setPackageSubprograms',
        'package': packageName.toUpperCase(),
        'subprograms': [
          for (final s in subs)
            {
              'name': s.name,
              'kind': s.kind.toUpperCase(),
              'args': [
                for (final a in s.arguments)
                  if (a.name.isNotEmpty && a.name != '(RETURN)')
                    {'name': a.name, 'type': a.dataType, 'inOut': a.inOut},
              ],
            },
        ],
      });
      _enqueue((ctrl) async {
        await ctrl.runJavaScript('monacoReceiveMessage($payload)');
      });
    } catch (_) {}
  }

  /// Carga los atributos de un TYPE objeto y los envía a Monaco.
  Future<void> sendTypeAttributesFor(
    String typeName, {
    String ambiente = 'Desa',
  }) async {
    try {
      final attrs = await SchemaService.instance.getTypeAttributes(
        typeName,
        ambiente: ambiente,
      );
      final payload = jsonEncode({
        'action': 'setTypeAttributes',
        'type': typeName.toUpperCase(),
        'attributes': [
          for (final a in attrs) {'name': a.name, 'type': a.dataType},
        ],
      });
      _enqueue((ctrl) async {
        await ctrl.runJavaScript('monacoReceiveMessage($payload)');
      });
    } catch (_) {}
  }

  /// Carga los argumentos de un procedimiento o función suelto y los envía
  /// a Monaco para sugerir la notación nombrada dentro de los paréntesis.
  Future<void> sendObjectArgumentsFor(
    String objectName, {
    String ambiente = 'Desa',
  }) async {
    try {
      final args = await SchemaService.instance.getObjectArguments(
        objectName,
        ambiente: ambiente,
      );
      final payload = jsonEncode({
        'action': 'setObjectArguments',
        'object': objectName.toUpperCase(),
        'args': [
          for (final a in args)
            if (a.name.isNotEmpty && a.name != '(RETURN)')
              {'name': a.name, 'type': a.dataType, 'inOut': a.inOut},
        ],
      });
      _enqueue((ctrl) async {
        await ctrl.runJavaScript('monacoReceiveMessage($payload)');
      });
    } catch (_) {}
  }

  /// Precarga la firma de [name] si corresponde a un objeto con parámetros:
  /// argumentos para procedimientos y funciones, atributos para los types.
  Future<void> prefetchSignatureFor(
    String name, {
    String ambiente = 'Desa',
  }) async {
    final ref = name.toUpperCase();
    try {
      final schema = await SchemaService.instance.getMetadata(
        ambiente: ambiente,
      );
      final type = schema.objects
          .cast<({String name, String type, String owner})?>()
          .firstWhere((o) => o?.name.toUpperCase() == ref, orElse: () => null)
          ?.type;
      if (type == 'TYPE') {
        await sendTypeAttributesFor(ref, ambiente: ambiente);
      } else if (type == 'PROCEDURE' || type == 'FUNCTION') {
        await sendObjectArgumentsFor(ref, ambiente: ambiente);
      }
    } catch (_) {}
  }

  /// Resuelve el tipo de [name] en el schema y envía a Monaco los datos que
  /// correspondan: subprogramas del package, atributos del type o columnas.
  Future<void> sendMembersFor(String name, {String ambiente = 'Desa'}) async {
    final ref = name.toUpperCase();
    try {
      final schema = await SchemaService.instance.getMetadata(
        ambiente: ambiente,
      );
      final type = schema.objects
          .cast<({String name, String type, String owner})?>()
          .firstWhere((o) => o?.name.toUpperCase() == ref, orElse: () => null)
          ?.type;
      if (type == 'PACKAGE') {
        await sendPackageSubprogramsFor(ref, ambiente: ambiente);
        return;
      }
      if (type == 'TYPE') {
        await sendTypeAttributesFor(ref, ambiente: ambiente);
        return;
      }
    } catch (_) {
      // sin schema disponible → intentar como tabla
    }
    await sendColumnsFor(ref, ambiente: ambiente);
  }

  /// Carga las columnas de [tableName] y las envía a Monaco.

  /// Se llama automáticamente cuando el usuario escribe "TABLA.".
  Future<void> sendColumnsFor(
    String tableName, {
    String ambiente = 'Desa',
  }) async {
    try {
      final cols = await SchemaService.instance.getColumns(
        tableName,
        ambiente: ambiente,
      );
      final payload = jsonEncode({
        'action': 'setTableColumns',
        'table': tableName.toUpperCase(),
        'columns': cols
            .map((c) => {'name': c.name, 'type': c.dataType})
            .toList(),
      });
      _enqueue((ctrl) async {
        await ctrl.runJavaScript('monacoReceiveMessage($payload)');
      });
    } catch (_) {}
  }

  // fm.MonacoEditor owns the controller lifecycle — only release the reference.
  void dispose() {
    _disposed = true;
    _ctrl = null;
    _ready = false;
    _pending.clear();
  }
}

// Alias para que el panel siga usando `MonacoController` sin cambios.
typedef MonacoController = MonacoEditorController;

// ─── Widget ──────────────────────────────────────────────────────────────────
class MonacoEditorWidget extends StatefulWidget {
  final MonacoEditorController controller;
  final String initialCode;
  final String language; // 'plsql' | 'javascript'
  final bool darkTheme;
  final String ambiente; // 'Desa' | 'Demo' | 'QA' | 'Prod'
  final ValueChanged<String>? onChanged;
  final void Function(int line, int col)? onCursorChanged;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final VoidCallback? onExecuteCurrent;
  final VoidCallback? onExecuteAll;

  const MonacoEditorWidget({
    super.key,
    required this.controller,
    required this.initialCode,
    this.language = 'plsql',
    this.darkTheme = true,
    this.ambiente = 'Desa',
    this.onChanged,
    this.onCursorChanged,
    this.onError,
    this.onExecuteCurrent,
    this.onExecuteAll,
  });

  @override
  State<MonacoEditorWidget> createState() => _MonacoEditorWidgetState();
}

class _MonacoEditorWidgetState extends State<MonacoEditorWidget> {
  final GlobalKey _editorAreaKey = GlobalKey();
  StreamSubscription<fm.Range?>? _selectionSub;
  StreamSubscription<fm.MonacoEvent>? _contextMenuEventSub;
  final _completions = MonacoOracleCompletionsManager();
  final List<fm.MonacoActionRegistration> _registeredActions = [];
  fm.MonacoController? _rawCtrl;
  String _currentText = '';
  String _lastContextMenuWord = '';
  int _lastCursorLine = 1;
  int _lastCursorCol = 1;

  @override
  void initState() {
    super.initState();
    _currentText = widget.initialCode;
    editorThemeStore.addListener(_onEditorThemeChanged);
  }

  void _onEditorThemeChanged() {
    widget.controller.setTheme(editorThemeStore.monacoTheme);
  }

  fm.EditorOptions get _editorOptions => fm.EditorOptions(
    language: widget.language == 'javascript'
        ? fm.MonacoLanguage.javascript
        : fm.MonacoLanguage.sql,
    theme: editorThemeStore.monacoTheme,
    fontSize: 14,
    minimap: const fm.MonacoMinimapOptions(enabled: true),
    wordWrap: fm.MonacoWordWrap.off,
    lineNumbers: fm.MonacoLineNumbers.on,
    renderWhitespace: fm.RenderWhitespace.none,
    tabSize: 2,
    quickSuggestions: true,
    parameterHints: true,
    suggestOnTriggerCharacters: true,
    bracketPairColorization: true,
    contextMenu: false,
    extra: const {'fixedOverflowWidgets': true},
  );

  bool _isWordChar(String c) => RegExp(r'\w').hasMatch(c);

  String? _wordAtCachedPosition() {
    if (_currentText.isEmpty) return null;
    final lines = _currentText.split('\n');
    final line0 = _lastCursorLine - 1;
    if (line0 < 0 || line0 >= lines.length) return null;
    final line = lines[line0];
    final col = (_lastCursorCol - 1).clamp(0, line.length);
    int start = col;
    while (start > 0 && _isWordChar(line[start - 1])) {
      start--;
    }
    int end = col;
    while (end < line.length && _isWordChar(line[end])) {
      end++;
    }
    if (start == end) return null;
    return line.substring(start, end);
  }

  Future<String?> _wordAtContextMenu() async {
    if (_lastContextMenuWord.isNotEmpty) {
      final word = _lastContextMenuWord;
      _lastContextMenuWord = '';
      return word;
    }

    final ctrl = _rawCtrl;
    if (ctrl != null) {
      try {
        final js = await ctrl.evaluateJavaScript<String>(
          '(()=>{'
          'try{'
          'if(window._fmContextWord&&window._fmContextWord.length>0){'
          '  var w=window._fmContextWord;'
          '  window._fmContextWord="";'
          '  return w;'
          '}'
          'var p=window.editor.getPosition();'
          'var m=window.editor.getModel();'
          'if(!p||!m)return null;'
          'var w2=m.getWordAtPosition(p);'
          'return w2?w2.word:null;'
          '}catch(e){return null;}'
          '})()',
        );
        if (js != null && js.isNotEmpty) return js;
      } catch (e) {
        debugPrint('[CtxMenu] JS eval failed: $e');
      }
    }

    return _wordAtCachedPosition();
  }

  Future<void> _goToDefinitionAtCursor() async {
    if (!mounted) return;
    try {
      final word = await _wordAtContextMenu();
      if (word == null || word.isEmpty) return;

      final upperWord = word.toUpperCase();
      var schema = SchemaService.instance.getCached(ambiente: widget.ambiente);
      schema ??= await SchemaService.instance.getMetadata(
        ambiente: widget.ambiente,
      );

      String? name;
      String? objectType;

      final obj = schema.objects.where((o) => o.name == upperWord).firstOrNull;
      if (obj != null) {
        name = obj.name;
        objectType = obj.type;
      } else if (schema.tables.contains(upperWord)) {
        name = upperWord;
        objectType = 'TABLE';
      } else if (schema.views.contains(upperWord)) {
        name = upperWord;
        objectType = 'VIEW';
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (name != null && objectType != null) {
          openSourceWindow(
            context,
            name: name,
            objectType: objectType,
            ambiente: widget.ambiente,
          );
        } else {
          AppToast.info('No se encontró definición para "$word"');
        }
      });
    } catch (e, st) {
      debugPrint('[GotoDef] Error: $e\n$st');
    }
  }

  Future<void> _showInfoEventoAtCursor() async {
    if (!mounted) return;
    final word = await _wordAtContextMenu();
    if (word == null || word.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showInfoEventoWindow(context, word, widget.ambiente);
      }
    });
  }

  Future<void> _openInfoEventoWindow() async {
    if (!mounted) return;
    final word = _wordAtCachedPosition()?.trim() ?? '';
    final esCodigo = word.isNotEmpty && RegExp(r'^\d{3,}$').hasMatch(word);
    showInfoEventoWindow(context, esCodigo ? word : '', widget.ambiente);
  }

  Future<void> _showInfoDatoAtCursor() async {
    if (!mounted) return;
    final word = await _wordAtContextMenu();
    if (word == null || word.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showInfoDatoWindow(context, word, widget.ambiente);
      }
    });
  }

  Future<void> _openInfoDatoWindow() async {
    if (!mounted) return;
    final word = _wordAtCachedPosition()?.trim() ?? '';
    final esCodigo = word.isNotEmpty && RegExp(r'^\d{3,}$').hasMatch(word);
    showInfoDatoWindow(context, esCodigo ? word : '', widget.ambiente);
  }

  Future<void> _openAutorizacionesWindow() async {
    if (!mounted) return;
    showAutorizacionesWindow(context, widget.ambiente);
  }

  Future<void> _ejecutarProcedimiento() async {
    if (!mounted) return;
    String cd = '';
    final ctrl = _rawCtrl;
    if (ctrl != null) {
      try {
        final selected = await ctrl.evaluateJavaScript<String>(
          r'(()=>{'
          r'  try {'
          r'    const s = window.editor.getSelection();'
          r'    if (!s || s.isEmpty()) return null;'
          r'    return window.editor.getModel().getValueInRange(s) || null;'
          r'  } catch(e) { return null; }'
          r'})()',
        );
        if (selected != null &&
            selected.trim().isNotEmpty &&
            !selected.contains('\n') &&
            selected.trim().length < 100) {
          cd = selected.trim().toUpperCase();
        }
      } catch (_) {}
    }
    if (cd.isEmpty) {
      final word = await _wordAtContextMenu();
      if (word != null && word.trim().isNotEmpty) {
        cd = word.trim().toUpperCase();
      }
    }
    if (cd.isEmpty) {
      cd = procedimientosProvider.procedimientoActual?.cdProcedimiento ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showEjecutarProcedimientoWindow(context, cd, widget.ambiente);
      }
    });
  }

  Future<void> _ejecutarLlamadaPlsql() async {
    if (!mounted) return;
    String? objetoInicial;
    final ctrl = _rawCtrl;
    if (ctrl != null) {
      try {
        final selected = await ctrl.evaluateJavaScript<String>(
          r'(()=>{'
          r'  try {'
          r'    const s = window.editor.getSelection();'
          r'    if (!s || s.isEmpty()) return null;'
          r'    return window.editor.getModel().getValueInRange(s) || null;'
          r'  } catch(e) { return null; }'
          r'})()',
        );
        if (selected != null &&
            selected.trim().isNotEmpty &&
            !selected.contains('\n') &&
            selected.trim().length < 100) {
          objetoInicial = selected.trim();
        }
      } catch (_) {}
    }
    if (objetoInicial == null) {
      final word = await _wordAtContextMenu();
      if (word != null &&
          word.trim().isNotEmpty &&
          !RegExp(r'^\d+$').hasMatch(word)) {
        objetoInicial = word.trim();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showEjecutarLlamadaWindow(
          context,
          ambiente: widget.ambiente,
          objeto: objetoInicial,
        );
      }
    });
  }

  Future<void> _copySelectionToClipboard() async {
    final ctrl = _rawCtrl;
    if (ctrl == null) return;
    final selected = await ctrl.evaluateJavaScript<String>(
      r'(()=>{'
      r'  try {'
      r'    var aux = window.__fmAuxInput ? window.__fmAuxInput() : null;'
      r'    if (aux) {'
      r'      var start = aux.selectionStart, end = aux.selectionEnd;'
      r'      if (start != null && end != null && start !== end) {'
      r'        return aux.value.substring(start, end);'
      r'      }'
      r'      return null;'
      r'    }'
      r'    const s = window.editor.getSelection();'
      r'    if (!s || s.isEmpty()) return null;'
      r'    return window.editor.getModel().getValueInRange(s) || null;'
      r'  } catch(e) { return null; }'
      r'})()',
    );
    if (selected == null || selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    AppToast.info('Copiado al portapapeles');
  }

  Future<void> _cutSelectionToClipboard() async {
    final ctrl = _rawCtrl;
    if (ctrl == null) return;
    final selected = await ctrl.evaluateJavaScript<String>(
      r'(()=>{'
      r'  try {'
      r'    var aux = window.__fmAuxInput ? window.__fmAuxInput() : null;'
      r'    if (aux) {'
      r'      var start = aux.selectionStart, end = aux.selectionEnd;'
      r'      if (start != null && end != null && start !== end) {'
      r'        var val = aux.value;'
      r'        var text = val.substring(start, end);'
      r'        aux.value = val.substring(0, start) + val.substring(end);'
      r'        aux.selectionStart = aux.selectionEnd = start;'
      r'        aux.focus();'
      r'        aux.dispatchEvent(new Event("input", { bubbles: true }));'
      r'        return text;'
      r'      }'
      r'      return null;'
      r'    }'
      r'    const s = window.editor.getSelection();'
      r'    if (!s || s.isEmpty()) return null;'
      r'    const m = window.editor.getModel();'
      r'    const t = m.getValueInRange(s) || null;'
      r'    if (!t) return null;'
      r'    window.editor.focus();'
      r'    window.editor.executeEdits("flutter-cut", [{ range: s, text: "", forceMoveMarkers: true }]);'
      r'    window.editor.pushUndoStop();'
      r'    return t;'
      r'  } catch(e) { return null; }'
      r'})()',
    );
    if (selected == null || selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    AppToast.info('Cortado al portapapeles');
  }

  Future<void> _pasteFromClipboard() async {
    final ctrl = _rawCtrl;
    if (ctrl == null) return;
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final literal = jsonEncode(text);

    await ctrl.evaluateJavaScript<String>(
      '(()=>{'
      '  try {'
      '    const t = $literal;'
      '    var aux = window.__fmAuxInput ? window.__fmAuxInput() : null;'
      '    if (aux) {'
      '      var start = aux.selectionStart != null ? aux.selectionStart : aux.value.length;'
      '      var end = aux.selectionEnd != null ? aux.selectionEnd : aux.value.length;'
      '      var val = aux.value || "";'
      '      aux.value = val.substring(0, start) + t + val.substring(end);'
      '      aux.selectionStart = aux.selectionEnd = start + t.length;'
      '      aux.focus();'
      '      aux.dispatchEvent(new Event("input", { bubbles: true }));'
      '      return "ok";'
      '    }'
      '    const ed = window.editor;'
      '    if (!ed) return "err";'
      '    ed.focus();'
      '    let sels = ed.getSelections();'
      '    if (!sels || sels.length === 0) {'
      '      const s = ed.getSelection();'
      '      sels = s ? [s] : [];'
      '    }'
      '    if (sels.length === 0) return "err";'
      '    ed.pushUndoStop();'
      '    ed.executeEdits("flutter-paste", sels.map(function(s){'
      '      return { range: s, text: t, forceMoveMarkers: true };'
      '    }));'
      '    ed.pushUndoStop();'
      '    return "ok";'
      '  } catch(e) { return "err"; }'
      '})()',
    );
  }

  void _showFlutterContextMenu(Offset localPos, String word) {
    final RenderBox? box =
        _editorAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final globalPos = box.localToGlobal(localPos);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
      Offset.zero & overlay.size,
    );

    final wordLabel = word.isNotEmpty
        ? (word.length > 20 ? '${word.substring(0, 20)}…' : word)
        : '';

    showMenu<_CtxMenuAction>(
      context: context,
      position: position,
      elevation: 6,
      items: [
        if (widget.onExecuteCurrent != null)
          const PopupMenuItem(
            value: _CtxMenuAction.executeCurrent,
            child: Row(
              children: [
                Icon(Icons.play_arrow_rounded, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Ejecutar sentencia actual')),
                Text(
                  'Ctrl+Enter',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        if (widget.onExecuteAll != null)
          const PopupMenuItem(
            value: _CtxMenuAction.executeAll,
            child: Row(
              children: [
                Icon(Icons.playlist_play_rounded, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Ejecutar todo el script')),
                Text('F5', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        if (widget.onExecuteCurrent != null || widget.onExecuteAll != null)
          const PopupMenuDivider(),
        const PopupMenuItem(
          value: _CtxMenuAction.find,
          child: Row(
            children: [
              Icon(Icons.search, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Buscar…')),
              Text(
                'Ctrl+F',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CtxMenuAction.gotoDef,
          enabled: word.isNotEmpty,
          child: Row(
            children: [
              const Icon(Icons.call_made, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  word.isNotEmpty ? 'Ir a "$wordLabel"' : 'Ir a definición',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'F12',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CtxMenuAction.infoEvento,
          enabled: word.isNotEmpty,
          child: Row(
            children: [
              const Icon(Icons.event_note, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  word.isNotEmpty
                      ? 'Info evento "$wordLabel"'
                      : 'Información del evento',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'Alt+I',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CtxMenuAction.infoDato,
          enabled: word.isNotEmpty,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  word.isNotEmpty
                      ? 'Info dato "$wordLabel"'
                      : 'Información del dato',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'Alt+D',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CtxMenuAction.ejecutar,
          child: const Row(
            children: [
              Icon(Icons.play_arrow_rounded, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Ejecutar procedimiento…')),
              Text('Alt+R', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CtxMenuAction.ejecutarLlamada,
          child: const Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Ejecutar objeto PL/SQL…')),
              Text(
                'Ctrl+Shift+E',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _CtxMenuAction.cut,
          child: Row(
            children: [
              Icon(Icons.cut, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Cortar')),
              Text(
                'Ctrl+X',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _CtxMenuAction.copy,
          child: Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Copiar')),
              Text(
                'Ctrl+C',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _CtxMenuAction.paste,
          child: Row(
            children: [
              Icon(Icons.paste, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Pegar')),
              Text(
                'Ctrl+V',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    ).then((action) {
      unawaited(_rawCtrl?.runJavaScript('window.__fmContextMenuAux = null;'));
      if (action == null || !mounted) return;
      switch (action) {
        case _CtxMenuAction.executeCurrent:
          widget.onExecuteCurrent?.call();
          break;
        case _CtxMenuAction.executeAll:
          widget.onExecuteAll?.call();
          break;
        case _CtxMenuAction.find:
          unawaited(
            _rawCtrl?.runJavaScript(
              'if(window.__fmOpenFind) window.__fmOpenFind();',
            ),
          );
          break;
        case _CtxMenuAction.gotoDef:
          unawaited(_goToDefinitionAtCursor());
          break;
        case _CtxMenuAction.infoEvento:
          unawaited(_showInfoEventoAtCursor());
          break;
        case _CtxMenuAction.infoDato:
          unawaited(_showInfoDatoAtCursor());
          break;
        case _CtxMenuAction.ejecutar:
          unawaited(_ejecutarProcedimiento());
          break;
        case _CtxMenuAction.ejecutarLlamada:
          unawaited(_ejecutarLlamadaPlsql());
          break;
        case _CtxMenuAction.cut:
          unawaited(_cutSelectionToClipboard());
          break;
        case _CtxMenuAction.copy:
          unawaited(_copySelectionToClipboard());
          break;
        case _CtxMenuAction.paste:
          unawaited(_pasteFromClipboard());
          break;
      }
    });
  }

  void _onReady(fm.MonacoController ctrl) {
    _rawCtrl = ctrl;
    widget.controller.attach(ctrl);
    _updateStatementSeparators(
      _currentText.isNotEmpty ? _currentText : widget.initialCode,
    );
    // Registrar los temas y luego aplicar el actual: sin este paso Monaco se
    // queda con su tema 'vs' claro por defecto hasta el próximo cambio.
    unawaited(
      EditorThemeStore.defineAllThemes(
        ctrl,
      ).then((_) => ctrl.setTheme(editorThemeStore.monacoTheme)),
    );
    _selectionSub = ctrl.onSelectionChanged.listen((range) {
      if (range != null) {
        _lastCursorLine = range.startLine;
        _lastCursorCol = range.startColumn;
        widget.onCursorChanged?.call(range.startLine, range.startColumn);
      }
    });

    // Parches JS sobre el WebView para sugerencias automáticas fluidas:
    // Tab acepta la sugerencia seleccionada, Enter produce salto de línea normal,
    // y quickSuggestions se activa mientras se escriben identificadores.
    unawaited(
      ctrl.runJavaScript(
        'try { window.editor.updateOptions({'
        '  acceptSuggestionOnEnter: "off",'
        '  tabCompletion: "on",'
        '  wordBasedSuggestions: "currentDocument",'
        '  quickSuggestions: { other: true, comments: false, strings: false }'
        '}); } catch(e) {}',
      ),
    );

    // Guard de foco y widget de búsqueda (resuelve foco en buscador y pegado en aux input)
    unawaited(ctrl.runJavaScript(_kFindAndFocusGuardJs));

    // Menú contextual reemplazado por uno Flutter nativo: captura el evento
    // nativo 'contextmenu' del DOM, evita el menú por defecto de Monaco y
    // reporta a Dart la posición/palabra para abrir el menú nativo Flutter.
    unawaited(
      ctrl.runJavaScript(
        'document.addEventListener("contextmenu",function(e){'
        '  e.preventDefault();'
        '  try {'
        '    var isAux = e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || (e.target.closest && e.target.closest(".find-widget")));'
        '    window.__fmContextMenuAux = isAux'
        '      ? (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA"'
        '          ? e.target'
        '          : document.querySelector(".find-widget .find-part input"))'
        '      : null;'
        '    if (!isAux && window.editor) {'
        '      try { window.editor.focus(); } catch(_) {}'
        '    }'
        '    var target = (!isAux && window.editor.getTargetAtClientPoint)'
        '      ? window.editor.getTargetAtClientPoint(e.clientX, e.clientY)'
        '      : null;'
        '    var pos = (target && target.position) || (!isAux ? window.editor.getPosition() : null);'
        '    var word = "";'
        '    if (pos) {'
        '      var w = window.editor.getModel().getWordAtPosition(pos);'
        '      word = w ? w.word : "";'
        '      var sel = window.editor.getSelection();'
        // Right-clicking inside an existing selection must preserve it (so
        // "Ejecutar sentencia actual" can run the selected text), not collapse
        // the cursor to the click point as a fresh selection would.
        '      var withinSel = sel && !sel.isEmpty() && sel.containsPosition(pos);'
        '      if (!withinSel) {'
        '        window.editor.setPosition(pos);'
        '      }'
        '    } else if (isAux && window.__fmContextMenuAux) {'
        '      var aux = window.__fmContextMenuAux;'
        '      var s = aux.selectionStart, end = aux.selectionEnd;'
        '      if (s != null && end != null && s !== end) {'
        '        word = aux.value.substring(s, end);'
        '      }'
        '    }'
        '    window.FlutterMonaco.emit("fmMenuOpening", {'
        '      x: e.clientX, y: e.clientY, word: word,'
        '      line: pos ? pos.lineNumber : 0,'
        '      col: pos ? pos.column : 0'
        '    });'
        '  } catch(_) {}'
        '},true);',
      ),
    );

    // Escucha fmMenuOpening para abrir el menú contextual nativo Flutter
    _contextMenuEventSub = ctrl.events.listen((event) {
      if (event is fm.MonacoUnknownEvent && event.name == 'fmMenuOpening') {
        final data = event.data;
        final word = (data['word'] as String?) ?? '';
        final line = (data['line'] as num?)?.toInt() ?? 0;
        final col = (data['col'] as num?)?.toInt() ?? 0;
        final x = (data['x'] as num?)?.toDouble() ?? 0.0;
        final y = (data['y'] as num?)?.toDouble() ?? 0.0;
        _lastContextMenuWord = word;
        if (line > 0) {
          _lastCursorLine = line;
          _lastCursorCol = col;
        }
        if (mounted) {
          _showFlutterContextMenu(Offset(x, y), word);
        }
      }
    });

    // Captura sincrónica de la palabra bajo el cursor al abrir menú
    unawaited(
      ctrl.runJavaScript(
        'try {'
        '  window._fmContextWord = "";'
        '  window.editor.onContextMenu(function(e) {'
        '    try {'
        '      var pos = (e.target && e.target.position)'
        '        || window.editor.getPosition();'
        '      if (!pos) return;'
        '      var w = window.editor.getModel().getWordAtPosition(pos);'
        '      window._fmContextWord = w ? w.word : "";'
        '      window.FlutterMonaco.emit("fmContextMenu", {'
        '        word: window._fmContextWord,'
        '        line: pos.lineNumber,'
        '        col: pos.column'
        '      });'
        '    } catch(_) {}'
        '  });'
        '} catch(ex) {}',
      ),
    );

    // Sistema completo de autocompletado Oracle:
    // - Palabras clave y plantillas PL/SQL y SQL
    // - Snippets de usuario (gestor de snippets)
    // - Variables dinámicas (:variable)
    // - Esquema dinámico Oracle (tablas, vistas, columnas contextuales del FROM,
    //   notación de punto TABLA./ALIAS., subprogramas de paquetes y tipos)
    unawaited(
      _completions.registerAll(
        ctrl,
        getText: () =>
            _currentText.isNotEmpty ? _currentText : widget.initialCode,
        getAmbiente: () => widget.ambiente,
      ),
    );

    // Cargar schema Oracle en background al abrir el editor
    widget.controller.loadAndSendSchema(ambiente: widget.ambiente);

    // Ctrl+F para abrir el buscador de forma controlada sin perder el foco
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.find'),
              label: 'Buscar en el documento',
              keybindings: [
                fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyF),
              ],
            ),
            () async {
              await ctrl.runJavaScript(
                'if(window.__fmOpenFind) window.__fmOpenFind();',
              );
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Atajos de teclado nativos en Monaco (resuelve captura de WebView2 en Windows):
    // Ctrl+Enter para ejecutar sentencia actual / selección
    if (widget.onExecuteCurrent != null) {
      unawaited(
        ctrl
            .addAction(
              const fm.MonacoActionDescriptor(
                id: fm.MonacoAction('sql.execute.current'),
                label: 'Ejecutar sentencia actual / selección',
                keybindings: [
                  fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.enter),
                ],
                precondition: 'editorTextFocus',
              ),
              () async {
                widget.onExecuteCurrent?.call();
              },
            )
            .then((action) => _registeredActions.add(action)),
      );
    }

    // F5 para ejecutar todo el script
    if (widget.onExecuteAll != null) {
      unawaited(
        ctrl
            .addAction(
              const fm.MonacoActionDescriptor(
                id: fm.MonacoAction('sql.execute.all'),
                label: 'Ejecutar todo el script',
                keybindings: [fm.MonacoKeybinding(key: fm.MonacoKey.f5)],
                precondition: 'editorTextFocus',
              ),
              () async {
                widget.onExecuteAll?.call();
              },
            )
            .then((action) => _registeredActions.add(action)),
      );
    }

    // F12: Ir a definición
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.goto.definition'),
              label: 'Ir a definición',
              keybindings: [fm.MonacoKeybinding(key: fm.MonacoKey.f12)],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.5,
              precondition: 'editorTextFocus',
            ),
            () async => _goToDefinitionAtCursor(),
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Alt+I: Información del evento
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.info.evento'),
              label: 'Información del evento',
              keybindings: [
                fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyI),
              ],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.6,
            ),
            () async {
              unawaited(_showInfoEventoAtCursor());
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Alt+D: Información del dato
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.info.dato'),
              label: 'Información del dato',
              keybindings: [
                fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyD),
              ],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.7,
            ),
            () async {
              unawaited(_showInfoDatoAtCursor());
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Alt+R: Ejecutar procedimiento dinámico…
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.ejecutar.procedimiento'),
              label: 'Ejecutar procedimiento dinámico…',
              keybindings: [
                fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyR),
              ],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.82,
            ),
            () async {
              unawaited(_ejecutarProcedimiento());
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Ctrl+Shift+E: Ejecutar objeto PL/SQL…
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.ejecutar.llamada'),
              label: 'Ejecutar objeto PL/SQL…',
              keybindings: [
                fm.MonacoKeybinding(
                  ctrlCmd: true,
                  shift: true,
                  key: fm.MonacoKey.keyE,
                ),
              ],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.83,
            ),
            () async {
              unawaited(_ejecutarLlamadaPlsql());
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Alt+E: Consultar evento…
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.buscar.evento'),
              label: 'Consultar evento…',
              keybindings: [
                fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyE),
              ],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.85,
            ),
            () async {
              unawaited(_openInfoEventoWindow());
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Alt+A: Consultar autorizaciones…
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.buscar.autorizacion'),
              label: 'Consultar autorizaciones…',
              keybindings: [
                fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyA),
              ],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.9,
            ),
            () async {
              unawaited(_openAutorizacionesWindow());
            },
          )
          .then((action) => _registeredActions.add(action)),
    );

    // Portapapeles (Ctrl+C, Ctrl+X, Ctrl+V)
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.clipboard.copy'),
              label: 'Copiar',
              keybindings: [
                fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyC),
              ],
            ),
            () async => _copySelectionToClipboard(),
          )
          .then((action) => _registeredActions.add(action)),
    );
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.clipboard.cut'),
              label: 'Cortar',
              keybindings: [
                fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyX),
              ],
            ),
            () async => _cutSelectionToClipboard(),
          )
          .then((action) => _registeredActions.add(action)),
    );
    unawaited(
      ctrl
          .addAction(
            const fm.MonacoActionDescriptor(
              id: fm.MonacoAction('custom.clipboard.paste'),
              label: 'Pegar',
              keybindings: [
                fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyV),
              ],
            ),
            () async => _pasteFromClipboard(),
          )
          .then((action) => _registeredActions.add(action)),
    );
  }

  @override
  void didUpdateWidget(MonacoEditorWidget old) {
    super.didUpdateWidget(old);
    if (old.language != widget.language) {
      widget.controller.setLanguage(widget.language);
    }
    if (old.ambiente != widget.ambiente && _rawCtrl != null) {
      unawaited(
        _completions.registerSchema(
          _rawCtrl!,
          getText: () =>
              _currentText.isNotEmpty ? _currentText : widget.initialCode,
          getAmbiente: () => widget.ambiente,
        ),
      );
    }
  }

  @override
  void dispose() {
    _contextMenuEventSub?.cancel();
    _selectionSub?.cancel();
    editorThemeStore.removeListener(_onEditorThemeChanged);
    for (final action in _registeredActions) {
      try {
        action.dispose();
      } catch (_) {}
    }
    _registeredActions.clear();
    _completions.dispose();
    _rawCtrl = null;
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _editorAreaKey,
      child: fm.MonacoEditor(
        initialText: widget.initialCode,
        options: _editorOptions,
        page: const fm.MonacoPageConfig(customCss: _kEditorCustomCss),
        contentDebounce: const Duration(milliseconds: 300),
        onReady: _onReady,
        onContentChanged: (code) {
          _currentText = code;
          widget.onChanged?.call(code);
          _checkDotTrigger(code);
          _updateStatementSeparators(code);
        },
        onError: widget.onError,
      ),
    );
  }

  /// Recalcula las líneas donde debe dibujarse el separador visual entre
  /// sentencias (todas menos la primera, que no necesita línea encima).
  void _updateStatementSeparators(String code) {
    final stmts = splitStatements(code);
    if (stmts.length < 2) {
      widget.controller.updateStatementSeparators(const []);
      return;
    }
    final lines = [for (final stmt in stmts.skip(1)) stmt.startLine + 1];
    widget.controller.updateStatementSeparators(lines);
  }

  /// Detecta cuando el usuario escribe "OBJETO." o "MI_PROC(" y carga bajo
  /// demanda columnas, subprogramas, atributos o argumentos según el caso.
  /// Se acotan a [_dotTriggerMaxCache] entradas para no crecer sin límite en
  /// sesiones largas, y los regex solo miran la cola del texto (no hace falta
  /// re-escanear documentos de miles de líneas en cada pulsación).
  static const _dotTriggerTailChars = 200;
  static const _dotTriggerMaxCache = 500;
  final _lastTableLoaded = <String>{};
  final _lastArgsLoaded = <String>{};

  void _checkDotTrigger(String code) {
    final tail = code.length > _dotTriggerTailChars
        ? code.substring(code.length - _dotTriggerTailChars)
        : code;

    // "PALABRA." al final del texto → miembros del objeto
    final dot = RegExp(r'\b(\w{3,})\.$').firstMatch(tail);
    if (dot != null) {
      final ref = dot.group(1)!.toUpperCase();
      if (_rememberTrigger(_lastTableLoaded, ref)) {
        widget.controller.sendMembersFor(ref, ambiente: widget.ambiente);
      }
      return;
    }

    // "MI_PROC(" al final → argumentos para la notación nombrada
    final call = RegExp(r'\b(\w{3,})\s*\($').firstMatch(tail);
    if (call != null) {
      final ref = call.group(1)!.toUpperCase();
      if (_rememberTrigger(_lastArgsLoaded, ref)) {
        widget.controller.sendObjectArgumentsFor(
          ref,
          ambiente: widget.ambiente,
        );
      }
      return;
    }

    // Palabra suelta que coincide con un objeto del schema → precargar su
    // firma para poder ofrecer el snippet de llamada al completar.
    final word = RegExp(r'\b(\w{3,})$').firstMatch(tail);
    if (word != null) {
      final ref = word.group(1)!.toUpperCase();
      if (_rememberTrigger(_lastArgsLoaded, ref)) {
        widget.controller.prefetchSignatureFor(ref, ambiente: widget.ambiente);
      }
    }
  }

  // Evita volver a pedir lo mismo; si la caché crece demasiado la reinicia
  // en vez de mantener un historial indefinido de objetos ya consultados.
  bool _rememberTrigger(Set<String> cache, String ref) {
    if (cache.contains(ref)) return false;
    if (cache.length >= _dotTriggerMaxCache) cache.clear();
    cache.add(ref);
    return true;
  }
}
