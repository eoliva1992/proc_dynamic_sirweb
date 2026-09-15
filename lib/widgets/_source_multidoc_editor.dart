part of 'object_source_page.dart';

// Single Monaco WebView with two documents — spec loads immediately, body after.
// Tab switching activates the corresponding document without recreating the WebView.
class _MultiDocSourceEditor extends StatefulWidget {
  final String spec;
  final String? body;
  final bool isDark;
  final String ambiente;
  final bool isPlSql;
  final String objectType;
  final TabController tabCtrl;
  final bool minimap;
  final bool wordWrap;
  final double fontSize;
  final void Function(fm.MonacoController)? onControllerReady;
  final void Function(String)? onSpecTextChanged;
  final void Function(String)? onBodyTextChanged;
  final void Function(int)? onSpecErrorsChanged;
  final void Function(int)? onBodyErrorsChanged;
  final void Function(List<PlSqlIssue>)? onSpecIssuesChanged;
  final void Function(List<PlSqlIssue>)? onBodyIssuesChanged;
  final void Function(bool checking)? onBackendChecking;

  /// Callback para navegar a la definición de un objeto Oracle desde el editor.
  final void Function(String name, String objectType)? onGotoDefinition;

  const _MultiDocSourceEditor({
    required this.spec,
    required this.body,
    required this.isDark,
    required this.ambiente,
    required this.isPlSql,
    required this.objectType,
    required this.tabCtrl,
    this.minimap = true,
    this.wordWrap = false,
    this.fontSize = 14,
    this.onControllerReady,
    this.onSpecTextChanged,
    this.onBodyTextChanged,
    this.onSpecErrorsChanged,
    this.onBodyErrorsChanged,
    this.onSpecIssuesChanged,
    this.onBodyIssuesChanged,
    this.onBackendChecking,
    this.onGotoDefinition,
  });

  @override
  State<_MultiDocSourceEditor> createState() => _MultiDocSourceEditorState();
}

class _MultiDocSourceEditorState extends State<_MultiDocSourceEditor> {
  fm.MonacoController? _ctrl;
  fm.MonacoDocument? _specDoc;
  fm.MonacoDocument? _bodyDoc;
  fm.MonacoCompletionRegistration? _kwReg;
  fm.MonacoCompletionRegistration? _schemaReg;
  fm.MonacoCompletionRegistration? _snippetsReg;
  fm.MonacoActionRegistration? _gotoDefAction;
  final List<fm.MonacoActionRegistration> _extraActions = [];
  StreamSubscription<fm.Range?>? _selectionSub;
  StreamSubscription<dynamic>? _contextMenuEventSub;
  final GlobalKey _editorAreaKey = GlobalKey();
  int _lastCursorLine = 1;
  int _lastCursorCol = 1;
  String _lastContextMenuWord = '';
  // Ver [_withCtrl]: el State puede sobrevivir al webview.
  bool _disposed = false;
  bool _specReady = false;
  bool _bodyReady = false;
  Timer? _debounce;
  int _checkGen = 0;
  bool _isBody = false;
  String _currentSpecCode = '';
  String _currentBodyCode = '';
  int? _fromExtractHash;
  Map<String, String> _fromExtractResult = {};

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

  @override
  void initState() {
    super.initState();
    widget.tabCtrl.addListener(_onTabChanged);
    snippetsRevision.addListener(_onSnippetsRevisionChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    widget.tabCtrl.removeListener(_onTabChanged);
    _debounce?.cancel();
    _selectionSub?.cancel();
    _contextMenuEventSub?.cancel();
    snippetsRevision.removeListener(_onSnippetsRevisionChanged);
    _disposeMonacoQuietly(() => _kwReg?.dispose());
    _disposeMonacoQuietly(() => _schemaReg?.dispose());
    _disposeMonacoQuietly(() => _snippetsReg?.dispose());
    _disposeMonacoQuietly(() => _gotoDefAction?.dispose());
    for (final a in _extraActions) {
      _disposeMonacoQuietly(() => a.dispose());
    }
    _extraActions.clear();
    editorThemeStore.removeListener(_onEditorThemeChanged2);
    _ctrl = null;
    _specDoc = null;
    _bodyDoc = null;
    super.dispose();
  }

  /// Ejecuta [action] contra el controller sólo si sigue vivo.
  Future<T?> _withCtrl<T>(
    Future<T> Function(fm.MonacoController ctrl) action,
  ) async {
    final ctrl = _ctrl;
    if (ctrl == null || _disposed || !mounted) return null;
    try {
      return await action(ctrl);
    } catch (e) {
      if (_isMonacoDisposedError(e)) {
        _ctrl = null;
        return null;
      }
      rethrow;
    }
  }

  /// Igual que [_withCtrl] pero para un documento concreto (spec/body), que
  /// vive dentro del mismo webview y rebota con el mismo error.
  Future<void> _withDoc(
    fm.MonacoDocument? doc,
    Future<void> Function(fm.MonacoDocument doc) action,
  ) async {
    if (doc == null || _ctrl == null || _disposed || !mounted) return;
    try {
      await action(doc);
    } catch (e) {
      if (_isMonacoDisposedError(e)) {
        _ctrl = null;
        return;
      }
      rethrow;
    }
  }

  void _onEditorThemeChanged2() {
    unawaited(_withCtrl((ctrl) => ctrl.setTheme(editorThemeStore.monacoTheme)));
  }

  void _onSnippetsRevisionChanged() {
    if (!mounted || _disposed) return;
    unawaited(_registerSnippetsCompletions());
  }

  Future<void> _registerSnippetsCompletions() async {
    final ctrl = _ctrl;
    if (ctrl == null || _disposed || !mounted) return;
    _disposeMonacoQuietly(() => _snippetsReg?.dispose());
    _snippetsReg = null;
    final reg = await registerUserSnippetCompletions(
      ctrl,
      id: 'multidoc-user-snippets',
    );
    if (!mounted || _disposed) {
      _disposeMonacoQuietly(() => reg?.dispose());
      return;
    }
    _snippetsReg = reg;
  }

  bool _isWordChar(String c) => RegExp(r'\w').hasMatch(c);

  String? _wordAtCachedPosition() {
    final code = _isBody ? _currentBodyCode : _currentSpecCode;
    if (code.isEmpty) return null;
    final lines = code.split('\n');
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

    final ctrl = _ctrl;
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
        debugPrint('[CtxMenu MultiDoc] JS eval failed: $e');
      }
    }

    return _wordAtCachedPosition();
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

  Future<void> _openAutorizacionesWindow() async {
    if (!mounted) return;
    showAutorizacionesWindow(context, widget.ambiente);
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

  Future<void> _copySelectionToClipboard() async {
    final selected = await _withCtrl(
      (ctrl) => ctrl.evaluateJavaScript<String>(
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
      ),
    );
    if (selected == null || selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selected));
    AppToast.info('Copiado al portapapeles');
  }

  Future<void> _cutSelectionToClipboard() async {
    final selected = await _withCtrl(
      (ctrl) => ctrl.evaluateJavaScript<String>(
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
        r'    window.editor.executeEdits("flutter-cut", [{ range: s, text: "", forceMoveMarkers: true }]);'
        r'    window.editor.pushUndoStop();'
        r'    return t;'
        r'  } catch(e) { return null; }'
        r'})()',
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

    final literal = jsonEncode(text);

    final result = await _withCtrl(
      (ctrl) => ctrl.evaluateJavaScript<String>(
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
        '      aux.dispatchEvent(new Event("input", { bubbles: true }));'
        '      return "ok";'
        '    }'
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

    await _withCtrl((ctrl) async {
      final pos = await ctrl.getCursorPosition();
      if (pos == null) return;
      await ctrl.document.insert(pos, text);
    });
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
      if (action == null || !mounted) return;
      switch (action) {
        case _CtxMenuAction.gotoDef:
          if (_ctrl != null) unawaited(_goToDefinition(_ctrl!));
          break;
        case _CtxMenuAction.infoEvento:
          unawaited(_showInfoEventoAtCursor());
          break;
        case _CtxMenuAction.infoDato:
          unawaited(_showInfoDatoAtCursor());
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

  Future<void> _goToDefinition(fm.MonacoController ctrl) async {
    if (!mounted) return;
    try {
      final word = await ctrl.evaluateJavaScript<String>(
        '(()=>{try{'
        'var p=window.editor.getPosition();'
        'var m=window.editor.getModel();'
        'if(!p||!m)return null;'
        'var w=m.getWordAtPosition(p);'
        'return w?w.word:null;'
        '}catch(e){return null;}})()',
      );
      if (word == null || word.isEmpty || !mounted) return;
      final upper = word.toUpperCase();
      final schema = SchemaService.instance.getCached(
        ambiente: widget.ambiente,
      );
      if (schema == null) return;

      String? name;
      String? objectType;
      final obj = schema.objects.where((o) => o.name == upper).firstOrNull;
      if (obj != null) {
        name = obj.name;
        objectType = obj.type;
      } else if (schema.tables.contains(upper)) {
        name = upper;
        objectType = 'TABLE';
      } else if (schema.views.contains(upper)) {
        name = upper;
        objectType = 'VIEW';
      }

      if (name == null || objectType == null) return;
      final n = name;
      final t = objectType;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onGotoDefinition?.call(n, t);
      });
    } catch (_) {}
  }

  void _onTabChanged() async {
    final wantsBody = widget.tabCtrl.index == 1;
    if (_isBody == wantsBody) return;
    _isBody = wantsBody;

    if (wantsBody) {
      final bodyDoc = _bodyDoc;
      if (bodyDoc != null) {
        await _withCtrl((ctrl) => ctrl.activateDocument(bodyDoc));
        if (widget.isPlSql && _currentBodyCode.isNotEmpty) {
          _scheduleCheck(_currentBodyCode, isBody: true);
        }
      }
      return;
    }

    final doc = _specDoc;
    if (doc != null) {
      await _withCtrl((ctrl) => ctrl.activateDocument(doc));
      if (widget.isPlSql && _currentSpecCode.isNotEmpty) {
        _scheduleCheck(_currentSpecCode, isBody: false);
      }
    }
  }

  Future<void> _onReady(fm.MonacoController ctrl) async {
    _ctrl = ctrl;
    widget.onControllerReady?.call(ctrl);
    editorThemeStore.addListener(_onEditorThemeChanged2);

    // Open spec FIRST so content is visible as fast as possible
    _specDoc = await ctrl.openDocument(
      text: widget.spec,
      language: fm.MonacoLanguage.sql,
      uri: Uri.parse('file:///source/spec.sql'),
    );
    await ctrl.activateDocument(_specDoc!);
    if (mounted) setState(() => _specReady = true);
    widget.onSpecTextChanged?.call(widget.spec);

    // Background setup after content is already visible
    await Future.wait([
      EditorThemeStore.defineAllThemes(ctrl),
      ctrl
          .registerStaticCompletions(
            id: 'plsql-multidoc-kw',
            languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
            triggerCharacters: const [' ', '.', '('],
            items: plsqlCompletionItems,
          )
          .then((r) => _kwReg = r),
    ]);
    await ctrl.setTheme(editorThemeStore.monacoTheme);

    _loadSchema(ctrl);
    _registerSchemaCompletions(ctrl);
    _registerSnippetsCompletions();

    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter:"off", tabCompletion:"on"'
      '}); } catch(e) {}',
    );
    await ctrl.runJavaScript(_kContextMenuFocusGuardJs);

    // Context menu native hook
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

    // Acciones y Keybindings
    final List<Future<fm.MonacoActionRegistration>> actionFutures = [];

    if (widget.onGotoDefinition != null) {
      actionFutures.add(
        ctrl.addAction(
          const fm.MonacoActionDescriptor(
            id: fm.MonacoAction('oracle.multidoc.goToDefinition'),
            label: 'Ir a definición',
            keybindings: [fm.MonacoKeybinding(key: fm.MonacoKey.f12)],
            contextMenuGroupId: 'navigation',
            contextMenuOrder: 1.5,
            precondition: 'editorTextFocus',
          ),
          () async => _goToDefinition(ctrl),
        ),
      );
    }

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.info.evento'),
          label: 'Información del evento',
          keybindings: [fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyI)],
          contextMenuGroupId: 'navigation',
          contextMenuOrder: 1.6,
        ),
        () async {
          unawaited(_showInfoEventoAtCursor());
        },
      ),
    );

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.info.dato'),
          label: 'Información del dato',
          keybindings: [fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyD)],
          contextMenuGroupId: 'navigation',
          contextMenuOrder: 1.7,
        ),
        () async {
          unawaited(_showInfoDatoAtCursor());
        },
      ),
    );

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.buscar.evento'),
          label: 'Consultar evento…',
          keybindings: [fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyE)],
          contextMenuGroupId: 'navigation',
          contextMenuOrder: 1.85,
        ),
        () async {
          unawaited(_openInfoEventoWindow());
        },
      ),
    );

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.buscar.autorizacion'),
          label: 'Consultar autorizaciones…',
          keybindings: [fm.MonacoKeybinding(alt: true, key: fm.MonacoKey.keyA)],
          contextMenuGroupId: 'navigation',
          contextMenuOrder: 1.9,
        ),
        () async {
          unawaited(_openAutorizacionesWindow());
        },
      ),
    );

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.clipboard.copy'),
          label: 'Copiar',
          keybindings: [
            fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyC),
          ],
        ),
        () async => _copySelectionToClipboard(),
      ),
    );

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.clipboard.cut'),
          label: 'Cortar',
          keybindings: [
            fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyX),
          ],
        ),
        () async => _cutSelectionToClipboard(),
      ),
    );

    actionFutures.add(
      ctrl.addAction(
        const fm.MonacoActionDescriptor(
          id: fm.MonacoAction('oracle.multidoc.clipboard.paste'),
          label: 'Pegar',
          keybindings: [
            fm.MonacoKeybinding(ctrlCmd: true, key: fm.MonacoKey.keyV),
          ],
        ),
        () async => _pasteFromClipboard(),
      ),
    );

    final registrations = await Future.wait(actionFutures);
    if (widget.onGotoDefinition != null && registrations.isNotEmpty) {
      _gotoDefAction = registrations.first;
      _extraActions.addAll(registrations.skip(1));
    } else {
      _extraActions.addAll(registrations);
    }

    _selectionSub = ctrl.onSelectionChanged.listen((range) {
      if (range != null) {
        _lastCursorLine = range.startLine;
        _lastCursorCol = range.startColumn;
      }
    });

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

    if (widget.isPlSql && widget.spec.isNotEmpty) {
      _currentSpecCode = widget.spec;
      _scheduleCheck(widget.spec, isBody: false);
    }

    // Load body in background so it's ready before the user switches tabs
    final body = widget.body;
    if (body != null && body.isNotEmpty) {
      widget.onBodyTextChanged?.call(body);
      _openBodyInBackground(ctrl, body);
    }
  }

  Future<void> _openBodyInBackground(
    fm.MonacoController ctrl,
    String body,
  ) async {
    final doc = await _withCtrl(
      (c) => c.openDocument(
        text: body,
        language: fm.MonacoLanguage.sql,
        uri: Uri.parse('file:///source/body.sql'),
      ),
    );
    if (doc == null || !mounted) return;
    _bodyDoc = doc;
    setState(() => _bodyReady = true);
    _currentBodyCode = body;
    if (_isBody) await _withCtrl((c) => c.activateDocument(doc));
    if (widget.isPlSql) _scheduleCheck(body, isBody: true);
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

  void _registerSchemaCompletions(fm.MonacoController ctrl) {
    _disposeMonacoQuietly(() => _schemaReg?.dispose());
    _schemaReg = null;
    SchemaService.instance
        .getMetadata(ambiente: widget.ambiente)
        .then((schema) async {
          // El editor pudo cerrarse mientras se resolvía el schema; si el
          // controller ya no está, no hay nada que registrar. Un rebote por
          // editor destruido cae en el .catchError final de esta cadena.
          if (!mounted || _disposed) return;
          final live = _ctrl;
          if (live == null) return;
          _schemaReg = await live.registerCompletions(
            id: 'multi-doc-schema',
            languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
            triggerCharacters: ['.', ' '],
            provider: (request) async {
              final line = request.lineText ?? '';
              final trigger = request.triggerCharacter;
              final fullText = _isBody ? _currentBodyCode : _currentSpecCode;
              if (trigger == '.' || line.endsWith('.')) {
                final dotMatch = _reDotPrefix.firstMatch(line);
                if (dotMatch != null) {
                  final realTable =
                      _extractFromTables(fullText)[dotMatch
                          .group(1)!
                          .toUpperCase()] ??
                      dotMatch.group(1)!.toUpperCase();
                  final cols = await SchemaService.instance.getColumns(
                    realTable,
                    ambiente: widget.ambiente,
                  );
                  return fm.CompletionList(
                    suggestions: cols
                        .map(
                          (c) => fm.CompletionItem(
                            label: c.name,
                            kind: fm.CompletionItemKind.field,
                            detail: '${c.dataType} · $realTable',
                            insertText: c.name,
                            sortText: '0${c.name}',
                          ),
                        )
                        .toList(),
                  );
                }
              }
              final upper = _wordBefore(line).toUpperCase();
              final suggestions = <fm.CompletionItem>[];
              for (final t in _extractFromTables(fullText).values.toSet()) {
                final cols =
                    schema.cachedColumns[t] ??
                    await SchemaService.instance.getColumns(
                      t,
                      ambiente: widget.ambiente,
                    );
                suggestions.addAll(
                  cols
                      .where((c) => upper.isEmpty || c.name.startsWith(upper))
                      .map(
                        (c) => fm.CompletionItem(
                          label: c.name,
                          kind: fm.CompletionItemKind.field,
                          detail: '${c.dataType} · $t',
                          sortText: '1${c.name}',
                        ),
                      ),
                );
              }
              suggestions.addAll(
                schema.tables
                    .where((t) => upper.isEmpty || t.startsWith(upper))
                    .map(
                      (t) => fm.CompletionItem(
                        label: t,
                        kind: fm.CompletionItemKind.classType,
                        detail: 'TABLE',
                        sortText: '2$t',
                      ),
                    ),
              );
              suggestions.addAll(
                schema.views
                    .where((v) => upper.isEmpty || v.startsWith(upper))
                    .map(
                      (v) => fm.CompletionItem(
                        label: v,
                        kind: fm.CompletionItemKind.interfaceType,
                        detail: 'VIEW',
                        sortText: '3$v',
                      ),
                    ),
              );
              suggestions.addAll(
                schema.objects
                    .where((o) => upper.isEmpty || o.name.startsWith(upper))
                    .map(
                      (o) => fm.CompletionItem(
                        label: o.name,
                        kind: o.type == 'FUNCTION'
                            ? fm.CompletionItemKind.functionType
                            : o.type == 'PACKAGE'
                            ? fm.CompletionItemKind.module
                            : fm.CompletionItemKind.method,
                        detail: o.type,
                        sortText: '4${o.name}',
                      ),
                    ),
              );
              return fm.CompletionList(
                suggestions: suggestions.take(50).toList(),
              );
            },
          );
        })
        .catchError((_) {});
  }

  Map<String, String> _extractFromTables(String sql) {
    final hash = sql.hashCode ^ sql.length;
    if (hash == _fromExtractHash) return _fromExtractResult;
    final result = <String, String>{};
    void add(String table, String? alias) {
      final t = table.toUpperCase();
      result[t] = t;
      if (alias != null && alias.isNotEmpty) result[alias.toUpperCase()] = t;
    }

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
    final fromBlock = _reFromBlock.firstMatch(sql)?.group(1) ?? '';
    for (final m in _reAliasBlock.allMatches(fromBlock)) {
      if (!reserved.contains(m.group(2)!.toUpperCase())) {
        add(m.group(1)!, m.group(2));
      }
    }
    for (final m in _reFromSimple.allMatches(sql)) {
      add(m.group(1)!, null);
    }
    for (final m in _reJoin.allMatches(sql)) {
      add(m.group(1)!, m.group(2));
    }
    _fromExtractHash = sql.hashCode ^ sql.length;
    _fromExtractResult = result;
    return result;
  }

  String _wordBefore(String line) =>
      _reWordEnd.firstMatch(line)?.group(1) ?? '';

  // Debounce scales with size — larger files need more idle time before validation fires
  void _scheduleCheck(String code, {required bool isBody}) {
    _debounce?.cancel();
    final gen = ++_checkGen;
    // Clear stale markers immediately so the editor doesn't show obsolete results
    final doc = isBody ? _bodyDoc : _specDoc;
    unawaited(_withDoc(doc, (d) => d.clearMarkers(owner: 'plsql-checker')));
    if (isBody) {
      widget.onBodyErrorsChanged?.call(0);
      widget.onBodyIssuesChanged?.call([]);
    } else {
      widget.onSpecErrorsChanged?.call(0);
      widget.onSpecIssuesChanged?.call([]);
    }
    final ms = code.length > 15000 ? 3500 : 1200;
    _debounce = Timer(Duration(milliseconds: ms), () {
      if (!mounted || _disposed || _ctrl == null) return;
      _checkSyntax(code, gen, isBody: isBody);
    });
  }

  Future<void> _checkSyntax(
    String code,
    int gen, {
    required bool isBody,
  }) async {
    final ctrl = _ctrl;
    if (ctrl == null || code.isEmpty) return;
    widget.onBackendChecking?.call(true);
    try {
      // PACKAGE BODY requires a different objectType for the backend validator
      final objType = (isBody && widget.objectType == 'PACKAGE')
          ? 'PACKAGE BODY'
          : widget.objectType;
      final errors = await SchemaService.instance.validateSyntax(
        code,
        objType,
        ambiente: widget.ambiente,
      );
      if (!mounted || gen != _checkGen) return; // user typed again — discard
      final doc = isBody ? _bodyDoc : _specDoc;
      if (doc == null) return;
      final issues = errors
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
      final errCount = issues
          .where((e) => e.severity == fm.MarkerSeverity.error)
          .length;
      if (isBody) {
        widget.onBodyErrorsChanged?.call(errCount);
        widget.onBodyIssuesChanged?.call(issues);
      } else {
        widget.onSpecErrorsChanged?.call(errCount);
        widget.onSpecIssuesChanged?.call(issues);
      }
      await _withDoc(
        doc,
        (d) => d.setMarkers([
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
              source: 'Oracle',
            ),
        ], owner: 'plsql-checker'),
      );
    } finally {
      if (mounted) widget.onBackendChecking?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        KeyedSubtree(
          key: _editorAreaKey,
          child: fm.MonacoEditor(
            initialText: '',
            options: fm.EditorOptions(
              language: fm.MonacoLanguage.sql,
              theme: editorThemeStore.monacoTheme,
              fontSize: widget.fontSize,
              minimap: fm.MonacoMinimapOptions(enabled: widget.minimap),
              lineNumbers: fm.MonacoLineNumbers.on,
              wordWrap: widget.wordWrap
                  ? fm.MonacoWordWrap.on
                  : fm.MonacoWordWrap.off,
              renderWhitespace: fm.RenderWhitespace.none,
              tabSize: 2,
              // Ver code_editor_panel.dart: fuerza a que el menú contextual,
              // sugerencias y hover se rendericen dentro del contenedor del
              // editor en vez de anclados a document.body, evitando que los
              // clics del mouse no se registren en el WebView2 embebido.
              extra: const {'fixedOverflowWidgets': true},
            ),
            contentDebounce: const Duration(milliseconds: 600),
            onReady: _onReady,
            onContentChanged: (text) {
              if (_isBody) {
                _currentBodyCode = text;
                widget.onBodyTextChanged?.call(text);
                if (widget.isPlSql) _scheduleCheck(text, isBody: true);
              } else {
                _currentSpecCode = text;
                widget.onSpecTextChanged?.call(text);
                if (widget.isPlSql) _scheduleCheck(text, isBody: false);
              }
            },
          ),
        ),
        if (!_specReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando especificación...'),
          ),
        if (_isBody && !_bodyReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando cuerpo...'),
          ),
      ],
    );
  }
}
