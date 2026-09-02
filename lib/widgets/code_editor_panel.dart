import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:http/http.dart' as http;
import 'package:mobx/mobx.dart' show reaction, ReactionDisposer;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dato_info.dart';
import '../models/autorizacion_proceso.dart';
import '../models/ejecucion_procedimiento.dart';
import '../models/evento_info.dart';
import '../models/llamada_plsql.dart';
import '../models/procedimiento.dart';
import '../models/snippet.dart';
import '../models/uso_procedimiento.dart';
import '../models/variable_dinamica.dart';
import '../providers/procedimientos_provider.dart';
import '../services/schema_service.dart';
import '../services/sirweb_service.dart';
import '../services/snippet_service.dart';
import 'constellation_background.dart';
import 'ambiente_selector.dart';
import '_editor_oracle_theme.dart';
import '_editor_themes.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import 'procedure_diff_panel.dart';
import '../services/editor_draft_service.dart';
import 'app_toast.dart';
import 'source_float_window.dart';

part '_editor_toolbar_widgets.dart';
part '_editor_variables_overlay.dart';
part '_editor_outline_panel.dart';
part '_editor_snippets_overlay.dart';
part '_editor_float_window.dart';
part '_editor_info_evento_modal.dart';
part '_editor_info_dato_modal.dart';
part '_editor_info_usos_modal.dart';
part '_editor_ejecutar_modal.dart';
part '_editor_llamada_modal.dart';
part '_editor_info_autorizacion_modal.dart';
part '_editor_navigation.dart';
part '_editor_options_prefs.dart';
part '_editor_completions_system.dart';
part '_editor_save_compile.dart';
part '_editor_build_methods.dart';

// Máximo de caracteres permitidos para validación backend de Oracle DDL.
const _kBackendSizeLimit = 100 * 1024; // 100 KB

/// Formatea una duración en milisegundos y segundos, ej: `1450 ms (1.45 s)`.
String _formatearTiempoMsYSeg(int ms, {String prefix = ''}) {
  final double seg = ms / 1000.0;
  final String segStr;
  if (ms < 10) {
    segStr = seg.toStringAsFixed(3);
  } else {
    segStr = seg.toStringAsFixed(2);
  }
  return '$prefix$ms ms ($segStr s)';
}

enum _SaveStatus { idle, saving, saved, error }

enum _CompileStatus { idle, compiling, ok, error }

enum _CtxMenuAction { gotoDef, infoEvento, infoDato, copy, cut, paste }

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
  /// `PKG.` o `PKG.PRE` → captura el objeto y el miembro parcial que se escribe.
  static final _reDotMember = RegExp(r'([A-Za-z]\w*)\.(\w*)$');

  /// `MI_PROC(` o `MI_PKG.MI_PROC(...` → objeto, miembro y lo ya escrito
  /// dentro de los paréntesis (para sugerir parámetros con notación nombrada).
  static final _reCallOpen = RegExp(
    r'([A-Za-z]\w*)(?:\.([A-Za-z]\w*))?\s*\(([^()]*)$',
  );
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
  // El State puede seguir vivo mientras MonacoEditor ya destruyó su
  // controller (cierre del panel, recreación del webview, hot reload).
  // Cualquier llamada posterior lanza MonacoDisposedError, así que se
  // marca el estado y se anula la referencia — ver [_withCtrl].
  bool _disposed = false;
  Timer? _debounce;
  Timer? _backendDebounce;
  Timer? _declareDebounce;

  // Multi-documento: un editor, múltiples modelos con undo stack independiente
  final Map<String, MonacoDocument> _docs = {};
  final List<Procedimiento> _openProcs = [];
  String? _activeProcId;

  // Decoraciones para resaltar líneas con errores (independientes de markers)
  MonacoDecorationSet? _errorDecos;
  MonacoCompletionRegistration? _completionReg;
  MonacoCompletionRegistration? _variablesReg;
  MonacoCompletionRegistration? _schemaReg; // tablas, columnas, objetos Oracle
  MonacoCompletionRegistration? _snippetsReg;
  MonacoCompletionRegistration? _declareVarsReg; // variables del bloque DECLARE
  String _editorFullText = '';
  // Cache for _extractFromTables — avoids regex on full text for each keystroke
  int? _fromExtractHash;
  Map<String, String> _fromExtractResult = {};
  // Precomputed map from schema objects; rebuilt once when schema loads
  Map<String, String>? _cachedSchemaObjTypes;
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
  final Set<String> _modifiedProcs = {};
  final Map<String, int> _errorCounts = {};
  final Map<String, List<PlSqlIssue>> _compileErrorsPerProc = {};
  final Map<String, List<PlSqlIssue>> _backendIssuesPerProc = {};
  bool _backendChecking = false;
  int _backendCheckVersion = 0;
  MonacoActionRegistration? _zoomInAction;
  MonacoActionRegistration? _zoomOutAction;
  MonacoActionRegistration? _saveAction;
  MonacoActionRegistration? _compileAction;
  MonacoActionRegistration? _gotoDefAction;
  MonacoActionRegistration? _infoEventoAction;
  MonacoActionRegistration? _infoDatoAction;
  MonacoActionRegistration? _infoUsosAction;
  MonacoActionRegistration? _ejecutarAction;
  MonacoActionRegistration? _copyAction;
  MonacoActionRegistration? _cutAction;
  MonacoActionRegistration? _pasteAction;
  Timer? _saveTimer;
  Timer? _draftDebounce;
  _SaveStatus _saveStatus = _SaveStatus.idle;
  _CompileStatus _compileStatus = _CompileStatus.idle;
  String? _lastSaveError;
  bool _showProblemsPanel = false;
  double _problemsPanelHeight = 180.0;
  final Map<String, bool> _draftVisible = {}; // procId → show restore banner
  final GlobalKey _varsButtonKey = GlobalKey();

  // ── Outline & docked panels ───────────────────────────────────────────
  bool _showOutline = false;
  List<_OutlineItem> _outlineItems = const [];
  bool _varsDocked = false;

  // ── Tab scroll overflow indicators ────────────────────────────────────
  final _tabsScrollCtrl = ScrollController();
  bool _tabsCanScrollLeft = false;

  // Last cursor position — kept in sync via onSelectionChanged for goto-definition
  int _lastCursorLine = 1;
  int _lastCursorCol = 1;
  StreamSubscription<Range?>? _selectionSub;

  // Word captured when the context menu opens (via fmMenuOpening event).
  // Used as secondary fallback in _wordAtContextMenu().
  String _lastContextMenuWord = '';
  StreamSubscription<MonacoEvent>? _contextMenuEventSub;
  StreamSubscription<bool>? _focusChangedSub;
  Timer? _ctxMenuSuppressTimer;
  bool _suppressFocusRecovery = false;
  bool _tabsCanScrollRight = false;

  // ── Menú contextual: Monaco/WebView2 no entrega los clics del mouse al
  // menú contextual nativo de Monaco de forma fiable en este stack
  // (WebView2 en modo composición / off-screen, mouse input sintético vía
  // ICoreWebView2CompositionController.SendMouseInput). Diagnosticado en
  // profundidad: el clic derecho abre el menú correctamente (mousedown/
  // mouseup/contextmenu SÍ llegan al DOM), pero el clic izquierdo posterior
  // sobre una opción del menú NUNCA llega al DOM (ni siquiera mousedown),
  // sin importar interactionEnabled, foco de Monaco (que de hecho nunca se
  // pierde), ni fixedOverflowWidgets — apunta a un bug de entrega de mouse
  // sintético específico de menús nativos abiertos por 'contextmenu' en
  // este WebView. El autocompletado (menú activado por teclado/izq. clic)
  // SÍ funciona con clics, confirmando que el problema es específico del
  // menú contextual, no genérico de todos los overlays de Monaco.
  //
  // Solución: se deshabilita el menú contextual NATIVO de Monaco
  // (`contextMenu: false` en EditorOptions) y se reemplaza por un menú
  // 100% Flutter (`showMenu`) posicionado en las coordenadas del clic
  // derecho, reutilizando las mismas acciones (_goToDefinitionAtCursor,
  // _showInfoEventoAtCursor, etc.) que ya funcionan vía teclado.
  final GlobalKey _editorAreaKey = GlobalKey();

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
    _tabsScrollCtrl.addListener(_onTabsScroll);
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
    } else if (old.procedimiento.deTexto != widget.procedimiento.deTexto) {
      // Mismo procedimiento, texto distinto: el panel se monta con la versión
      // que trae el listado y recibe después la versión completa del backend.
      _refreshProcText(widget.procedimiento);
    }
    if (old.ambiente != widget.ambiente) {
      AppToast.info('Ambiente cambiado a ${widget.ambiente}');
    }
  }

  /// Sincroniza el documento con una versión más reciente del mismo
  /// procedimiento, respetando los cambios sin guardar del usuario.
  Future<void> _refreshProcText(Procedimiento proc) async {
    final id = proc.cdProcedimiento;
    final i = _openProcs.indexWhere((p) => p.cdProcedimiento == id);
    if (i >= 0) _openProcs[i] = proc;
    // Nunca pisar ediciones locales ni un draft restaurado.
    if (_modifiedProcs.contains(id)) return;
    final doc = _docs[id];
    if (doc == null) return;
    await _withCtrl((_) => doc.setText(proc.deTexto));
    if (!mounted) return;
    _editorFullText = proc.deTexto;
    widget.onCodeChanged?.call(proc.deTexto);
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _backendDebounce?.cancel();
    _declareDebounce?.cancel();
    editorThemeStore.removeListener(_onEditorThemeChanged);
    // MonacoEditor puede haber destruido el controller antes que este State,
    // en cuyo caso liberar los registros lanza MonacoDisposedError. Como ya
    // se están destruyendo del lado del webview, se ignora ese fallo.
    _disposeQuietly(() => _completionReg?.dispose());
    _disposeQuietly(() => _variablesReg?.dispose());
    _disposeQuietly(() => _schemaReg?.dispose());
    _disposeQuietly(() => _snippetsReg?.dispose());
    _disposeQuietly(() => _declareVarsReg?.dispose());
    _variablesReaction?.call();
    _disposeQuietly(() => _errorDecos?.dispose());
    _disposeQuietly(() => _zoomInAction?.dispose());
    _disposeQuietly(() => _zoomOutAction?.dispose());
    _disposeQuietly(() => _saveAction?.dispose());
    _disposeQuietly(() => _compileAction?.dispose());
    _saveTimer?.cancel();
    _draftDebounce?.cancel();
    _disposeQuietly(() => _gotoDefAction?.dispose());
    _disposeQuietly(() => _infoEventoAction?.dispose());
    _disposeQuietly(() => _infoDatoAction?.dispose());
    _disposeQuietly(() => _infoUsosAction?.dispose());
    _disposeQuietly(() => _ejecutarAction?.dispose());
    _disposeQuietly(() => _copyAction?.dispose());
    _disposeQuietly(() => _cutAction?.dispose());
    _disposeQuietly(() => _pasteAction?.dispose());
    _selectionSub?.cancel();
    _contextMenuEventSub?.cancel();
    _focusChangedSub?.cancel();
    _ctxMenuSuppressTimer?.cancel();
    _tabsScrollCtrl
      ..removeListener(_onTabsScroll)
      ..dispose();
    // Se anula al final: los callbacks async pendientes que se resuelvan
    // después de esto verán null en vez de un controller destruido.
    _errorDecos = null;
    _ctrl = null;
    super.dispose();
  }

  // ── Acceso seguro al controller ────────────────────────────────────────

  /// Ejecuta [action] contra el controller de Monaco sólo si sigue vivo.
  ///
  /// `MonacoController` no expone `isDisposed`, y muchas rutas de este panel
  /// son asíncronas (timers de debounce, respuestas del backend, `compute`,
  /// futures de diálogos). Si el widget se destruye mientras una de esas
  /// operaciones está en vuelo, la llamada rebota con `MonacoDisposedError`.
  /// Este helper centraliza el guard y degrada a null en vez de propagar.
  Future<T?> _withCtrl<T>(
    Future<T> Function(MonacoController ctrl) action,
  ) async {
    final ctrl = _ctrl;
    if (ctrl == null || _disposed || !mounted) return null;
    try {
      return await action(ctrl);
    } on MonacoDisposedError {
      // El editor se destruyó mientras la operación estaba en vuelo.
      _ctrl = null;
      _errorDecos = null;
      return null;
    } catch (e) {
      // flutter_monaco no siempre usa MonacoDisposedError: algunas rutas
      // (webview recreado, canal cerrado) lanzan StateError/PlatformException
      // con el mismo significado. Se filtra por mensaje para no tragar
      // errores reales.
      if (_isDisposedError(e)) {
        _ctrl = null;
        _errorDecos = null;
        return null;
      }
      rethrow;
    }
  }

  /// Igual que [_withCtrl] pero para el set de decoraciones de error, que vive
  /// dentro del mismo webview y también rebota una vez destruido.
  Future<void> _withErrorDecos(
    Future<void> Function(MonacoDecorationSet decos) action,
  ) async {
    final decos = _errorDecos;
    if (decos == null || _ctrl == null || _disposed || !mounted) return;
    try {
      await action(decos);
    } catch (e) {
      if (_isDisposedError(e)) {
        _errorDecos = null;
        _ctrl = null;
        return;
      }
      rethrow;
    }
  }

  /// Ejecuta [action] ignorando los fallos por editor ya destruido, tanto
  /// síncronos como los del `Future` que pueda devolver.
  /// Pensado para `dispose()`, donde `MonacoEditor` puede haber liberado el
  /// controller antes que este State libere sus registros.
  static void _disposeQuietly(Object? Function() action) {
    void report(Object e) {
      if (!_isDisposedError(e)) {
        debugPrint('[CodeEditorPanel] error al liberar recurso: $e');
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

  static bool _isDisposedError(Object e) {
    if (e is MonacoDisposedError) return true;
    final msg = e.toString();
    return msg.contains('MonacoDisposedError') ||
        msg.contains('has been disposed');
  }

  /// Libera un registro de completions ignorando el fallo por editor ya
  /// destruido (el registro vive dentro del webview, que puede haberse ido).
  Future<void> _disposeRegQuietly(MonacoCompletionRegistration? reg) async {
    if (reg == null) return;
    try {
      await reg.dispose();
    } catch (e) {
      if (!_isDisposedError(e)) rethrow;
    }
  }

  // ── Setup al estar listo ────────────────────────────────────────────────

  Future<void> _onReady(MonacoController ctrl) async {
    _ctrl = ctrl;
    final proc = widget.procedimiento;

    // ── Fase 1 — camino crítico: mostrar el código cuanto antes ───────────
    // El draft es I/O de disco y los temas viajan al WebView: son operaciones
    // independientes, así que se lanzan a la vez en lugar de encadenarlas.
    // El protocolo de flutter_monaco correlaciona respuestas por id, de modo
    // que admite varias llamadas en vuelo sin mezclarlas.
    final draftFuture = EditorDraftService.load(
      proc.cdProcedimiento,
      widget.ambiente,
    );
    final themeFuture = EditorThemeStore.defineAllThemes(ctrl)
        .then((_) => ctrl.setTheme(editorThemeStore.monacoTheme))
        .catchError((_) {});

    final draft = await draftFuture;
    final hasDraft = draft != null && draft != proc.deTexto;
    final text = hasDraft ? draft : proc.deTexto;

    final doc = await ctrl.openDocument(
      text: text,
      language: _langFor(proc),
      uri: _uriFor(proc),
    );
    _docs[proc.cdProcedimiento] = doc;
    await ctrl.activateDocument(doc);
    await themeFuture;

    // Cachear el texto completo antes del primer keystroke para que outline y
    // completions funcionen desde el arranque, y reportarlo para que
    // currentEditorCode quede seteado.
    _editorFullText = text;
    widget.onCodeChanged?.call(text);
    if (hasDraft && mounted) {
      setState(() {
        _modifiedProcs.add(proc.cdProcedimiento);
        _draftVisible[proc.cdProcedimiento] = true;
      });
      widget.onDirtyChanged?.call(true);
    }

    _applyEditorOptions();

    // ── Fase 2 — el resto, fuera del camino crítico ───────────────────────
    if (_disposed || !mounted) return;
    unawaited(_setupEditorExtras(ctrl, proc));
  }

  /// Parches JS sobre el WebView. No bloquean la primera pintura del código.
  Future<void> _installEditorPatches(MonacoController ctrl) async {
    // Tab acepta sugerencias, Enter NO (solo nueva línea).
    // Also force quickSuggestions on so completions fire while typing identifiers.
    await ctrl.runJavaScript(
      'try { window.editor.updateOptions({'
      '  acceptSuggestionOnEnter: "off",'
      '  tabCompletion: "on",'
      '  wordBasedSuggestions: "currentDocument",'
      '  quickSuggestions: { other: true, comments: false, strings: false }'
      '}); } catch(e) {}',
    );

    // forceFocus (editor-api.js) calls window.focus → document.body.focus →
    // ed.focus → ta.focus in that order. document.body.focus() runs FIRST and
    // is enough to blur the find-widget input (or an open context menu, see
    // below) before our other patches fire. Block all four paths whenever
    // .find-widget.visible OR a Monaco context/action menu is present, then
    // use a focusout fallback to return focus to the find input as a safety
    // net.
    //
    // Context menu note: flutter_monaco's own forceFocus() has an idempotency
    // guard that no-ops when the editor's textarea already owns
    // document.activeElement (avoiding a caret flicker), but its own source
    // comment admits that guard does NOT cover the case where a right-click
    // context menu currently owns focus — calling document.body.focus() then
    // "tears down an open context menu" (their words) before the click on a
    // menu item is processed by the browser. flutter_monaco's pointerDown
    // handler calls forceFocus() on every click while Monaco reports blurred
    // (which is exactly the state while its own context menu is open), so
    // clicking ANY context menu item — built-in or custom — re-triggers this
    // and closes the menu out from under the click. Guarding here, at the
    // JS focus() calls forceFocus() actually uses, fixes it regardless of
    // Dart-side widget rebuild timing.
    await ctrl.runJavaScript(
      '(function(){'
      '  function isFindOpen(){'
      '    var fw=document.querySelector(".find-widget");'
      '    if(fw&&fw.classList.contains("visible")) return true;'
      // Monaco appends its right-click context menu (and action/dropdown
      // menus) as a `.context-view.monaco-menu-container` element and
      // removes it from the DOM on close, so mere presence means it is open.
      '    if(document.querySelector(".monaco-menu-container")) return true;'
      '    return false;'
      '  }'
      '  function patchEl(el){'
      '    if(!el||el._fp) return;'
      '    el._fp=true;'
      '    var o=el.focus.bind(el);'
      '    el.focus=function(opts){ if(!isFindOpen()) o(opts); };'
      '  }'
      // Block document.body.focus() — this is the first call in forceFocus
      '  if(!document.body._fp){'
      '    document.body._fp=true;'
      '    var ob=document.body.focus.bind(document.body);'
      '    document.body.focus=function(){ if(!isFindOpen()) ob(); };'
      '  }'
      '  function tryPatch(){'
      '    patchEl(document.querySelector(".monaco-editor .inputarea"));'
      '    patchEl(document.querySelector(".monaco-editor .native-edit-context"));'
      '    if(window.editor&&!window.editor._fp){'
      '      window.editor._fp=true;'
      '      var oe=window.editor.focus.bind(window.editor);'
      '      window.editor.focus=function(){ if(!isFindOpen()) oe(); };'
      '    }'
      '  }'
      '  tryPatch();'
      '  var obs=new MutationObserver(tryPatch);'
      '  obs.observe(document.body,{childList:true,subtree:true});'
      // Fallback: if find input loses focus while widget is open, return it
      '  document.addEventListener("focusout",function(e){'
      '    if(!isFindOpen()) return;'
      '    var inp=document.querySelector(".find-widget .find-part input");'
      '    if(!inp||e.target!==inp) return;'
      '    setTimeout(function(){ if(isFindOpen()) inp.focus(); },0);'
      '  },true);'
      // Ctrl+F: wait for .visible class to be added, then focus the input
      '  document.addEventListener("keydown",function(e){'
      '    if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==="f"){'
      '      requestAnimationFrame(function(){'
      '        requestAnimationFrame(function(){'
      '          var inp=document.querySelector(".find-widget .find-part input");'
      '          if(inp) inp.focus();'
      '        });'
      '      });'
      '    }'
      '  },true);'
      '})()',
    );

    // ── Menú contextual reemplazado por uno Flutter nativo (ver docs en el
    // campo _editorAreaKey). Captura el evento nativo 'contextmenu' del DOM
    // (100% fiable, a diferencia del click posterior sobre un menú de
    // Monaco), evita el menú de Monaco (ya deshabilitado vía
    // EditorOptions.contextMenu:false, pero preventDefault por si acaso) y
    // reporta a Dart la palabra/posición bajo el cursor + coordenadas de
    // pantalla para abrir el menú Flutter en el lugar correcto.
    await ctrl.runJavaScript(
      'document.addEventListener("contextmenu",function(e){'
      '  e.preventDefault();'
      '  try {'
      '    var target = window.editor.getTargetAtClientPoint'
      '      ? window.editor.getTargetAtClientPoint(e.clientX, e.clientY)'
      '      : null;'
      '    var pos = (target && target.position) || window.editor.getPosition();'
      '    var word = "";'
      '    if (pos) {'
      '      var w = window.editor.getModel().getWordAtPosition(pos);'
      '      word = w ? w.word : "";'
      '      window.editor.setPosition(pos);'
      '    }'
      '    window.FlutterMonaco.emit("fmMenuOpening", {'
      '      x: e.clientX, y: e.clientY, word: word,'
      '      line: pos ? pos.lineNumber : 0,'
      '      col: pos ? pos.column : 0'
      '    });'
      '  } catch(_) {}'
      '},true);',
    );
  }

  /// Registros, acciones y listeners del editor. Se ejecuta después de que el
  /// código ya es visible, y agrupa en paralelo todo lo que antes era una
  /// cadena de ~20 `await` secuenciales (cada uno un round-trip al WebView).
  Future<void> _setupEditorExtras(
    MonacoController ctrl,
    Procedimiento proc,
  ) async {
    // Completions: las cuatro registraciones son independientes entre sí.
    final completionsFuture = Future.wait([
      ctrl
          .registerStaticCompletions(
            id: 'plsql-keywords',
            languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
            triggerCharacters: [' ', '.', '('],
            items: plsqlCompletionItems,
          )
          .then((r) => _completionReg = r),
      _registerVariableCompletions(),
      _registerSnippetCompletions(),
      _registerDeclareVarCompletions(),
    ]);

    _variablesReaction = reaction(
      (_) => procedimientosProvider.variablesDinamicas.toList(),
      (_) {
        if (_ctrl != null) _registerVariableCompletions();
      },
    );

    // Completion dinámico (tablas, columnas y objetos Oracle) y parches JS:
    // ambos son fire-and-forget, no hay que esperarlos para seguir.
    _registerSchemaCompletions(ctrl);
    unawaited(_installEditorPatches(ctrl));

    // LSP: intentar conectar sql-language-server si está instalado
    _tryConnectLsp(ctrl);

    // Conjunto de decoraciones para líneas con errores + las 11 acciones
    // custom, todas en paralelo.
    await Future.wait([
      ctrl.createDecorationSet().then((d) => _errorDecos = d),
      completionsFuture,
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.zoom.increase'),
              label: 'Aumentar tamaño de fuente',
              keybindings: [
                MonacoKeybinding(ctrlCmd: true, key: MonacoKey.equal),
              ],
            ),
            () async {
              if (mounted) {
                _toggle(() => _fontSize = (_fontSize + 2).clamp(10, 28));
              }
            },
          )
          .then((a) => _zoomInAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.zoom.decrease'),
              label: 'Reducir tamaño de fuente',
              keybindings: [
                MonacoKeybinding(ctrlCmd: true, key: MonacoKey.minus),
              ],
            ),
            () async {
              if (mounted) {
                _toggle(() => _fontSize = (_fontSize - 2).clamp(10, 28));
              }
            },
          )
          .then((a) => _zoomOutAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.save'),
              label: 'Guardar procedimiento',
              keybindings: [
                MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyS),
              ],
            ),
            () async {
              unawaited(_saveCurrentDocument());
            },
          )
          .then((a) => _saveAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.compile'),
              label: 'Compilar procedimiento (Oracle)',
              keybindings: [MonacoKeybinding(key: MonacoKey.f5)],
            ),
            () async {
              unawaited(_compileCurrentDocument());
            },
          )
          .then((a) => _compileAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.goto.definition'),
              label: 'Ir a definición',
              keybindings: [MonacoKeybinding(key: MonacoKey.f12)],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.5,
            ),
            () async => _goToDefinitionAtCursor(),
          )
          .then((a) => _gotoDefAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.info.evento'),
              label: 'Información del evento',
              keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyI)],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.6,
            ),
            () async {
              unawaited(_showInfoEventoAtCursor());
            },
          )
          .then((a) => _infoEventoAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.info.dato'),
              label: 'Información del dato',
              keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyD)],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.7,
            ),
            () async {
              unawaited(_showInfoDatoAtCursor());
            },
          )
          .then((a) => _infoDatoAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.info.usos'),
              label: 'Usos del procedimiento',
              keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyU)],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.8,
            ),
            () async {
              unawaited(_showUsosProcedimiento());
            },
          )
          .then((a) => _infoUsosAction = a),
      // Abre la ventana de ejecución del procedimiento dinámico.
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.ejecutar.procedimiento'),
              label: 'Ejecutar procedimiento dinámico…',
              keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyR)],
              contextMenuGroupId: 'navigation',
              contextMenuOrder: 1.82,
            ),
            () async {
              unawaited(_ejecutarProcedimiento());
            },
          )
          .then((a) => _ejecutarAction = a),
      // Abre la ventana de InfoEvento (sin requerir una palabra bajo el cursor).
      ctrl.addAction(
        MonacoActionDescriptor(
          id: MonacoAction('custom.buscar.evento'),
          label: 'Consultar evento…',
          keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyE)],
          contextMenuGroupId: 'navigation',
          contextMenuOrder: 1.85,
        ),
        () async {
          unawaited(_openInfoEventoWindow());
        },
      ),
      // Abre la ventana de consulta de autorizaciones de proceso.
      ctrl.addAction(
        MonacoActionDescriptor(
          id: MonacoAction('custom.buscar.autorizacion'),
          label: 'Consultar autorizaciones…',
          keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyA)],
          contextMenuGroupId: 'navigation',
          contextMenuOrder: 1.9,
        ),
        () async {
          unawaited(_openAutorizacionesWindow());
        },
      ),
      // Clipboard bridge: navigator.clipboard is blocked on file:// (WebView2).
      // These actions override Ctrl+C/X/V so Flutter's native clipboard is used.
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.clipboard.copy'),
              label: 'Copiar',
              keybindings: [
                MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyC),
              ],
            ),
            () async => _copySelectionToClipboard(),
          )
          .then((a) => _copyAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.clipboard.cut'),
              label: 'Cortar',
              keybindings: [
                MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyX),
              ],
            ),
            () async => _cutSelectionToClipboard(),
          )
          .then((a) => _cutAction = a),
      ctrl
          .addAction(
            MonacoActionDescriptor(
              id: MonacoAction('custom.clipboard.paste'),
              label: 'Pegar',
              keybindings: [
                MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyV),
              ],
            ),
            () async => _pasteFromClipboard(),
          )
          .then((a) => _pasteAction = a),
    ]);

    if (_disposed || !mounted) return;

    _scheduleCheck(proc.deTexto);

    // Cache cursor position for goto-definition fallback.
    _selectionSub = ctrl.onSelectionChanged.listen((range) {
      if (range != null) {
        _lastCursorLine = range.startLine;
        _lastCursorCol = range.startColumn;
      }
    });

    // Escucha fmMenuOpening (emitido por el listener 'contextmenu' de arriba)
    // para abrir nuestro menú contextual Flutter en el lugar del clic.
    _contextMenuEventSub = ctrl.events.listen((event) {
      if (event is MonacoUnknownEvent && event.name == 'fmMenuOpening') {
        final data = event.data;
        final word = (data['word'] as String?) ?? '';
        final line = (data['line'] as num?)?.toInt() ?? 0;
        final col = (data['col'] as num?)?.toInt() ?? 0;
        _lastContextMenuWord = word;
        if (line > 0) {
          _lastCursorLine = line;
          _lastCursorCol = col;
        }
        // Mientras el menú contextual está abierto, evitamos que pointerDown
        // interno de flutter_monaco robe foco nativo y cierre el menú.
        if (mounted && !_suppressFocusRecovery) {
          AppToast.warning('interactionEnabled = false (menú abierto)');
          setState(() => _suppressFocusRecovery = true);
        }
        _ctxMenuSuppressTimer?.cancel();
        _ctxMenuSuppressTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && _suppressFocusRecovery) {
            AppToast.warning('interactionEnabled = true (timeout)');
            setState(() => _suppressFocusRecovery = false);
          }
        });
      } else if (event is MonacoUnknownEvent &&
          event.name == 'fmMenuClickDebug') {
        // DIAGNÓSTICO TEMPORAL — ver el bloque JS en _onReady que lo emite.
        // Solo mostramos 'click' (clic izquierdo real) para aislar la señal
        // sin ruido del mousedown/mouseup/contextmenu del clic derecho.
        final d = event.data;
        if (d['phase'] == 'click') {
          AppToast.info(
            '[${d['phase']}] tag=${d['tag']} cls=${d['cls']} '
            'menus=${d['menus']} (${d['x']},${d['y']})',
            duration: const Duration(seconds: 8),
          );
        }
      }
    });

    // Cuando Monaco recupera el foco DOM del editor (el menú se cerró, sea
    // por ejecutar una acción o por cancelarse), se reactiva
    // interactionEnabled inmediatamente.
    _focusChangedSub = ctrl.onFocusChanged.listen((focused) {
      if (focused && mounted && _suppressFocusRecovery) {
        _ctxMenuSuppressTimer?.cancel();
        AppToast.warning('interactionEnabled = true (focus regained)');
        setState(() => _suppressFocusRecovery = false);
      }
    });

    // Captura la palabra bajo el cursor cuando se abre el menú contextual.
    // Necesario porque cuando el callback de la action se ejecuta,
    // _lastContextMenuWord ya tiene la palabra correcta del clic derecho.
    await ctrl.runJavaScript(
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
    );

    if (mounted && _showOutline) {
      compute(_parseOutlineItems, _editorFullText).then((items) {
        if (mounted) setState(() => _outlineItems = items);
      });
    }
  }

  void _toggleOutline() {
    if (_showOutline) {
      setState(() => _showOutline = false);
      _savePrefs();
      return;
    }
    // Show panel immediately, populate asynchronously
    setState(() => _showOutline = true);
    _savePrefs();
    final cached = _editorFullText.isNotEmpty
        ? _editorFullText
        : widget.procedimiento.deTexto;
    compute(_parseOutlineItems, cached).then((items) {
      if (mounted) setState(() => _outlineItems = items);
    });
    // Refresh from live Monaco text in case there are unsaved edits
    _withCtrl((ctrl) => ctrl.document.getText()).then((text) {
      if (text == null || text.isEmpty || !mounted) return;
      compute(_parseOutlineItems, text).then((items) {
        if (mounted) setState(() => _outlineItems = items);
      });
    });
  }

  void _onTabsScroll() {
    if (!_tabsScrollCtrl.hasClients) return;
    final pos = _tabsScrollCtrl.position;
    final canLeft = pos.pixels > 0;
    final canRight = pos.pixels < pos.maxScrollExtent;
    if (canLeft != _tabsCanScrollLeft || canRight != _tabsCanScrollRight) {
      setState(() {
        _tabsCanScrollLeft = canLeft;
        _tabsCanScrollRight = canRight;
      });
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
      // `EditorDraftService.load` es async: el editor pudo destruirse mientras
      // tanto, así que se vuelve a resolver el controller por el guard.
      final doc = await _withCtrl(
        (c) => c.openDocument(
          text: hasDraft ? draft : proc.deTexto,
          language: _langFor(proc),
          uri: _uriFor(proc),
        ),
      );
      if (doc == null) return;
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

    final doc = _docs[proc.cdProcedimiento];
    if (doc == null) return;
    await _withCtrl((c) => c.activateDocument(doc));
    // Report active document text so currentEditorCode reflects the switched-to proc
    if (mounted) {
      final text = await _withCtrl((c) => c.document.getText());
      if (text != null) {
        _editorFullText = text;
        widget.onCodeChanged?.call(text);
        if (_showOutline) {
          compute(_parseOutlineItems, text).then((items) {
            if (mounted) setState(() => _outlineItems = items);
          });
        }
      }
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

  // ── Checkers de sintaxis / Completions / LSP → _editor_completions_system.dart

  // ── Guardar / Compilar → _editor_save_compile.dart ─────────────────────────

  // ── Go to Definition / InfoEvento / InfoDato / Diff → _editor_navigation.dart

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
    await _disposeRegQuietly(_schemaReg);
    _schemaReg = null;

    // Usa getMetadata() — no dispara refresco, solo lee el caché disponible
    SchemaService.instance
        .getMetadata()
        .then((schema) async {
          if (!mounted || _disposed) return;

          // Rebuild once; reused every frame by _EditorOutlinePanel in build()
          _cachedSchemaObjTypes = schema.objects.fold(
            <String, String>{},
            (map, o) => map!..[o.name.toUpperCase()] = o.type,
          );

          _schemaReg = await _withCtrl(
            (c) => c.registerCompletions(
              id: 'oracle-schema',
              languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
              triggerCharacters: ['.', ' '],
              provider: (request) async {
                final line = request.lineText ?? '';
                final trigger = request.triggerCharacter;
                // Texto completo hasta la línea del cursor para detectar FROM en cualquier línea
                final fullText = _editorFullText;

                // ── Caso 1: "PKG.", "TYPE.", "ALIAS." o "TABLA." ─────────────────
                final dotMatch = _reDotMember.firstMatch(line);
                if (dotMatch != null) {
                  final ref = dotMatch.group(1)!.toUpperCase();
                  final member = dotMatch.group(2)!.toUpperCase();
                  final refType = _cachedSchemaObjTypes?[ref];

                  // 1.a) Package → sus procedimientos y funciones
                  if (refType == 'PACKAGE') {
                    return CompletionList(
                      suggestions: await _packageMemberCompletions(ref, member),
                    );
                  }

                  // 1.b) Type objeto → sus atributos
                  if (refType == 'TYPE') {
                    return CompletionList(
                      suggestions: await _typeMemberCompletions(ref, member),
                    );
                  }

                  // 1.c) Tabla, vista o alias → columnas
                  if (trigger == '.' ||
                      line.endsWith('.') ||
                      member.isNotEmpty) {
                    // Resolver alias en el texto completo del documento
                    final fromMap = _extractFromTables(fullText);
                    final realTable = fromMap[ref] ?? ref;

                    final cols = await SchemaService.instance.getColumns(
                      realTable,
                    );
                    return CompletionList(
                      suggestions: cols
                          .where(
                            (c) => member.isEmpty || c.name.startsWith(member),
                          )
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

                // ── Caso 1.d: dentro de "MI_PROC(" → parámetros con notación
                // nombrada, incluidos los miembros de un package.
                final callMatch = _reCallOpen.firstMatch(line);
                if (callMatch != null) {
                  final params = await _parameterCompletions(
                    owner: callMatch.group(1)!,
                    member: callMatch.group(2),
                    written: callMatch.group(3) ?? '',
                    prefix: _wordBefore(line),
                  );
                  if (params.isNotEmpty) {
                    return CompletionList(suggestions: params);
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
                final objMatches = schema.objects
                    .where((o) => upper.isEmpty || o.name.startsWith(upper))
                    .take(20)
                    .toList();

                // Precarga (cacheada) de la firma para armar el snippet de llamada:
                // argumentos de procs/funcs y atributos del constructor de types.
                if (upper.length >= 2) {
                  final pending = objMatches
                      .where(
                        (o) =>
                            o.type == 'PROCEDURE' ||
                            o.type == 'FUNCTION' ||
                            o.type == 'TYPE',
                      )
                      .take(10);
                  await Future.wait([
                    for (final o in pending)
                      if (o.type == 'TYPE')
                        SchemaService.instance.getTypeAttributes(
                          o.name,
                          ambiente: widget.ambiente,
                        )
                      else
                        SchemaService.instance.getObjectArguments(
                          o.name,
                          ambiente: widget.ambiente,
                        ),
                  ]);
                }

                suggestions.addAll(
                  objMatches.map((o) {
                    final call = _callInsertText(o.name, o.type);
                    return CompletionItem(
                      label: o.name,
                      kind: _objectKind(o.type),
                      detail: _callDetail(o.name, o.type),
                      documentation: _callDocumentation(o.name, o.type),
                      insertText: call.text,
                      insertTextRules: call.isSnippet
                          ? {InsertTextRule.insertAsSnippet}
                          : null,
                      sortText: '4${o.name}',
                    );
                  }),
                );

                return CompletionList(
                  suggestions: suggestions.take(50).toList(),
                );
              },
            ),
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

  Future<void> _copySelectionToClipboard() async {
    final selected = await _withCtrl(
      (ctrl) => ctrl.evaluateJavaScript<String>(
        r'(()=>{ try { const s=window.editor.getSelection(); if(!s||s.isEmpty())return null; return window.editor.getModel().getValueInRange(s)||null; } catch(e){ return null; } })()',
      ),
    );
    if (selected == null || selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    AppToast.info('Copiado al portapapeles');
  }

  Future<void> _cutSelectionToClipboard() async {
    final selected = await _withCtrl(
      (ctrl) => ctrl.evaluateJavaScript<String>(
        r'(()=>{ try { const s=window.editor.getSelection(); if(!s||s.isEmpty())return null; const m=window.editor.getModel(); const t=m.getValueInRange(s)||null; if(!t)return null; window.editor.executeEdits("flutter-cut",[{ range:s, text:"", forceMoveMarkers:true }]); window.editor.pushUndoStop(); return t; } catch(e){ return null; } })()',
      ),
    );
    if (selected == null || selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    AppToast.info('Cortado al portapapeles');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    // El texto se inyecta como literal JSON → escapa comillas, saltos de
    // línea y unicode sin romper el JS.
    final literal = jsonEncode(text);

    // executeEdits sobre la(s) selección(es) actual(es): reemplaza el rango
    // seleccionado en vez de insertar en el cursor (document.insert dejaba
    // el texto seleccionado intacto y pegaba al lado). Soporta multi-cursor.
    final result = await _withCtrl(
      (ctrl) => ctrl.evaluateJavaScript<String>(
        '(()=>{'
        '  try {'
        '    const t = $literal;'
        '    const ed = window.editor;'
        '    if (!ed) return "err";'
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
      ),
    );

    if (result == 'ok') return;

    // Fallback (puente JS caído): inserta en la posición del cursor.
    await _withCtrl((ctrl) async {
      final pos = await ctrl.getCursorPosition();
      if (pos == null) return;
      await ctrl.document.insert(pos, text);
    });
  }

  void _onEditorThemeChanged() {
    unawaited(_withCtrl((ctrl) => ctrl.setTheme(editorThemeStore.monacoTheme)));
  }

  Future<void> _registerVariableCompletions() async {
    await _disposeRegQuietly(_variablesReg);
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
    _variablesReg = await _withCtrl(
      (ctrl) => ctrl.registerStaticCompletions(
        id: 'plsql-variables',
        languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
        triggerCharacters: [':', ' ', '.', '('],
        items: items,
      ),
    );
  }

  Future<void> _registerSnippetCompletions() async {
    await _disposeRegQuietly(_snippetsReg);
    _snippetsReg = null;
    final snippets = await SnippetService.instance.loadAll();
    if (snippets.isEmpty) return;
    _snippetsReg = await _withCtrl(
      (ctrl) => ctrl.registerStaticCompletions(
        id: 'user-snippets',
        languages: [
          MonacoLanguage.sql,
          MonacoLanguage('plsql'),
          MonacoLanguage.javascript,
        ],
        triggerCharacters: [' '],
        items: [
          for (final s in snippets)
            CompletionItem(
              label: s.prefix,
              kind: CompletionItemKind.snippet,
              detail: s.name,
              documentation: s.description.isNotEmpty ? s.description : null,
              insertText: s.body,
              insertTextRules: {InsertTextRule.insertAsSnippet},
              // Sort above built-in keywords so user snippets appear first
              sortText: '0${s.prefix}',
            ),
        ],
      ),
    );
  }

  Future<void> _registerDeclareVarCompletions() async {
    if (_ctrl == null || _disposed || _isActiveJs) return;
    final code = _editorFullText.isNotEmpty
        ? _editorFullText
        : widget.procedimiento.deTexto;
    // Reuse the outline parser — already handles all DECLARE formats correctly
    final outlineItems = await compute(_parseOutlineItems, code);
    await _disposeRegQuietly(_declareVarsReg);
    _declareVarsReg = null;
    final seen = <String>{};
    final items = <CompletionItem>[];
    for (final item in outlineItems) {
      if (item.type != _OutlineItemType.variable &&
          item.type != _OutlineItemType.cursor) {
        continue;
      }
      if (!seen.add(item.name.toUpperCase())) continue;
      items.add(
        CompletionItem(
          label: item.name,
          kind: CompletionItemKind.variable,
          insertText: item.name,
          sortText: '0${item.name}',
        ),
      );
    }
    if (items.isEmpty) return;
    _declareVarsReg = await _withCtrl(
      (ctrl) => ctrl.registerStaticCompletions(
        id: 'plsql-declare-vars',
        languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
        triggerCharacters: [':', ' ', '.', '('],
        items: items,
      ),
    );
  }

  void _openSnippetsManager() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'snippets-dismiss',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) => const _SnippetsManagerDialog(),
    ).then((_) {
      if (mounted) _registerSnippetCompletions();
    });
  }

  // ── Guardar ────────────────────────────────────────────────────────────

  Future<void> _saveCurrentDocument() async {
    final onSave = widget.onSave;
    if (onSave == null || _saveStatus == _SaveStatus.saving) return;
    final code = await _withCtrl((ctrl) => ctrl.document.getText());
    if (code == null || !mounted) return;
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
              (compileIssues + (_backendIssuesPerProc[procId] ?? []))
                  .where((e) => e.severity == MarkerSeverity.error)
                  .length;
        });
        final ctrl = _ctrl;
        if (ctrl != null) {
          await ctrl.document.setMarkers([
            for (final e in [
              ...compileIssues,
              ...(_backendIssuesPerProc[procId] ?? []),
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
        }
        AppToast.warning(
          '${compileIssues.length} error${compileIssues.length == 1 ? '' : 'es'} de compilación Oracle',
        );
        if (mounted) setState(() => _showProblemsPanel = true);
      } else if (mounted && _compileErrorsPerProc.containsKey(procId)) {
        // Clear previous compile errors on a now-clean save
        setState(() => _compileErrorsPerProc.remove(procId));
        final ctrl = _ctrl;
        if (ctrl != null) {
          await ctrl.document.setMarkers([
            for (final e in [...(_backendIssuesPerProc[procId] ?? [])])
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
        _errorCounts[procId] =
            (serverErrors + (_backendIssuesPerProc[procId] ?? []))
                .where((e) => e.severity == MarkerSeverity.error)
                .length;
        _showProblemsPanel = true;
      });
      // Aplicar squiggles y decoraciones en Monaco para ver los errores en el código
      await _withCtrl(
        (ctrl) => ctrl.document.setMarkers([
          for (final e in [
            ...serverErrors,
            ...(_backendIssuesPerProc[procId] ?? []),
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
        ], owner: 'plsql-checker'),
      );
      await _withErrorDecos(
        (decos) => decos.set([
          for (final e in serverErrors)
            DecorationOptions.line(
              range: Range.lines(e.line, e.line),
              className: 'plsql-error-line',
              additionalOptions: {
                'overviewRuler': {'color': '#FF4444', 'position': 4},
                'minimap': {'color': '#FF4444', 'position': 1},
              },
            ),
        ]),
      );
      _saveTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
    }
  }

  // ── Compilar (usa el ANTLR4/Oracle del servidor) ─────────────────────

  Future<void> _compileCurrentDocument() async {
    final onCompile = widget.onCompile;
    if (onCompile == null || _compileStatus == _CompileStatus.compiling) return;
    final code = await _withCtrl((ctrl) => ctrl.document.getText());
    if (code == null || !mounted) return;
    setState(() => _compileStatus = _CompileStatus.compiling);
    try {
      await onCompile(code);
      if (!mounted) return;
      final rawCompileErrors = procedimientosProvider.lastCompileErrors;
      final procId = _activeProcId ?? '';
      if (rawCompileErrors.isNotEmpty) {
        final compileIssues = parseOracleCompileErrors(rawCompileErrors);
        setState(() {
          _compileErrorsPerProc[procId] = compileIssues;
          _errorCounts[procId] = ([
            ...compileIssues,
            ...(_backendIssuesPerProc[procId] ?? []),
          ]).where((e) => e.severity == MarkerSeverity.error).length;
          _compileStatus = _CompileStatus.error;
          _showProblemsPanel = true;
        });
        await _withCtrl(
          (ctrl) => ctrl.document.setMarkers([
            for (final e in [
              ...compileIssues,
              ...(_backendIssuesPerProc[procId] ?? []),
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
          ], owner: 'plsql-checker'),
        );
        await _withErrorDecos(
          (decos) => decos.set([
            for (final e in compileIssues)
              DecorationOptions.line(
                range: Range.lines(e.line, e.line),
                className: 'plsql-error-line',
                additionalOptions: {
                  'overviewRuler': {'color': '#FF4444', 'position': 4},
                  'minimap': {'color': '#FF4444', 'position': 1},
                },
              ),
          ]),
        );
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
        _errorCounts[procId] = errors
            .where((e) => e.severity == MarkerSeverity.error)
            .length;
        _showProblemsPanel = true;
      });
    }
    Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _compileStatus = _CompileStatus.idle);
    });
  }

  // ── Go to Definition / InfoEvento / InfoDato / Diff → _editor_navigation.dart

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
    _scheduleDeclareVarCompletions();
    _scheduleDraftSave(id, code);
    if (_showOutline) {
      compute(_parseOutlineItems, code).then((items) {
        if (mounted) setState(() => _outlineItems = items);
      });
    }
  }

  void _scheduleDeclareVarCompletions() {
    _declareDebounce?.cancel();
    _declareDebounce = Timer(
      const Duration(milliseconds: 1500),
      () => unawaited(_registerDeclareVarCompletions()),
    );
  }

  void _scheduleDraftSave(String? id, String code) {
    if (id == null) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 1500), () {
      EditorDraftService.save(id, widget.ambiente, code);
    });
  }

  Future<void> _discardDraft(String procId) async {
    final proc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == procId,
      orElse: () => widget.procedimiento,
    );
    final doc = _docs[procId];
    if (doc != null) {
      await _withCtrl((_) => doc.setText(proc.deTexto));
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

  // ── Opciones & Preferencias → _editor_options_prefs.dart ─────────────

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
          child: RepaintBoundary(
            child: Stack(
              children: [
                Row(
                  children: [
                    // Monaco editor — takes all remaining width
                    Expanded(
                      child: MonacoEditor(
                        initialText: widget.procedimiento.deTexto,
                        options: EditorOptions(
                          language: _langFor(widget.procedimiento),
                          theme: oracleDarkTheme,
                          fontSize: _fontSize,
                          minimap: MonacoMinimapOptions(enabled: _minimap),
                          wordWrap: _wordWrap
                              ? MonacoWordWrap.on
                              : MonacoWordWrap.off,
                          lineNumbers: _lineNumbers
                              ? MonacoLineNumbers.on
                              : MonacoLineNumbers.off,
                          renderWhitespace: _renderWhitespace
                              ? RenderWhitespace.all
                              : RenderWhitespace.none,
                          tabSize: 2,
                          bracketPairColorization: _bracketPairColorization,
                          stickyScroll: MonacoStickyScroll(
                            enabled: _stickyScroll,
                          ),
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
                          // fixedOverflowWidgets: renderiza el menú
                          // contextual, el widget de sugerencias y el hover
                          // DENTRO del contenedor del editor en vez de
                          // anclados a document.body con position:fixed.
                          // Sin esto, en el WebView2 embebido como Texture
                          // de Flutter los clics del mouse sobre esos
                          // widgets no se registran (desajuste de mapeo de
                          // coordenadas del puntero vs. el layout fixed de
                          // página completa), aunque la navegación por
                          // teclado sí funciona porque no depende de
                          // coordenadas. Mismo fix aplicado en el HTML
                          // legacy de Monaco (assets/monaco_editor.html).
                          extra: const {'fixedOverflowWidgets': true},
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
                        // Ver _suppressFocusRecovery: desactiva el
                        // pointerDown handler interno de flutter_monaco
                        // (que llama a requestNativeFocus, Win32 SetFocus)
                        // mientras el menú contextual nativo está abierto,
                        // evitando que ese robo de foco cierre el menú
                        // antes de que el clic en una opción se procese.
                        interactionEnabled: !_suppressFocusRecovery,
                      ),
                    ),
                    // Docked variables panel
                    if (_varsDocked)
                      Builder(
                        builder: (context) {
                          final dockedVars = _filteredVariables();
                          if (dockedVars.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _VarsDockedPanel(
                            vars: dockedVars,
                            onSelected: (v) async {
                              final ctrl = _ctrl;
                              if (ctrl == null) return;
                              final pos = await ctrl.getCursorPosition();
                              if (pos != null) {
                                await ctrl.document.insert(
                                  pos,
                                  ':${v.cdVariable}',
                                );
                              }
                            },
                            onUnpin: () {
                              setState(() => _varsDocked = false);
                              _savePrefs();
                            },
                          );
                        },
                      ),
                    // Outline sidebar
                    if (_showOutline)
                      _EditorOutlinePanel(
                        items: _outlineItems,
                        code: _editorFullText,
                        ambiente: widget.ambiente,
                        schemaObjects: _cachedSchemaObjTypes,
                        onItemTap: (line) async {
                          await _withCtrl((ctrl) async {
                            await ctrl.revealLine(line, center: true);
                            await ctrl.setCursorPosition(
                              Position(line: line, column: 1),
                            );
                          });
                        },
                        onClose: () {
                          setState(() => _showOutline = false);
                          _savePrefs();
                        },
                      ),
                  ],
                ),
                // Overlay flotante — indicador de schema (esquina inferior izquierda)
              ],
            ),
          ),
        ),
        // Panel de problemas (sintaxis + compilación Oracle)
        _buildProblemsPanel(context),
      ],
    );
  }
}
