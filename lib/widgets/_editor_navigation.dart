part of 'code_editor_panel.dart';

// ── Navegación: Go to Definition / Info Evento / Info Dato / Diff ─────────────

extension _EditorNavigationMethods on _CodeEditorPanelState {
  /// Extracts the identifier word at the cached cursor position from the in-memory text.
  String? _wordAtCachedPosition() {
    if (_editorFullText.isEmpty) return null;
    final lines = _editorFullText.split('\n');
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

  bool _isWordChar(String c) => RegExp(r'\w').hasMatch(c);

  /// Returns the word to look up for goto-definition.
  ///
  /// Priority:
  ///   1. Word captured synchronously when the context menu opened
  ///      (`_lastContextMenuWord`). Consumed on read.
  ///   2. JS IIFE — `window._fmContextWord` (synchronously set by onContextMenu)
  ///      then `editor.getPosition()` + `getWordAtPosition()`.
  ///   3. Pure-Dart extraction from the cached cursor position (last resort).
  Future<String?> _wordAtContextMenu() async {
    if (_lastContextMenuWord.isNotEmpty) {
      final word = _lastContextMenuWord;
      _lastContextMenuWord = '';
      return word;
    }

    final ctrl = _ctrl;
    if (ctrl != null) {
      try {
        // window._fmContextWord is set synchronously in the onContextMenu handler
        // BEFORE the fmContextMenu Dart event arrives. Using it here ensures
        // the word is available even when the Dart event hasn't been processed yet.
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
      final schema = SchemaService.instance.getCached(
        ambiente: widget.ambiente,
      );

      String? name;
      String? objectType;

      if (schema != null) {
        final obj = schema.objects
            .where((o) => o.name == upperWord)
            .firstOrNull;
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
      }

      debugPrint('[GotoDef] resolved: name=$name objectType=$objectType');

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
        _showInfoEventoModal(context, word, widget.ambiente);
      }
    });
  }

  /// Abre la ventana de InfoEvento desde la toolbar del editor.
  ///
  /// Si la palabra bajo el cursor parece un código de evento (solo dígitos)
  /// la usa como consulta inicial; si no, abre la ventana en modo búsqueda.
  Future<void> _openInfoEventoWindow() async {
    if (!mounted) return;
    final word = _wordAtCachedPosition()?.trim() ?? '';
    final esCodigo = word.isNotEmpty && RegExp(r'^\d{3,}$').hasMatch(word);
    _showInfoEventoModal(context, esCodigo ? word : '', widget.ambiente);
  }

  /// Abre la ventana de consulta de autorizaciones de proceso.
  ///
  /// Siempre abre sin filtro: la búsqueda la decide el usuario dentro de la
  /// ventana (tomar la palabra bajo el cursor producía filtros inesperados).
  Future<void> _openAutorizacionesWindow() async {
    if (!mounted) return;
    _showAutorizacionesModal(context, widget.ambiente);
  }

  Future<void> _showInfoDatoAtCursor() async {
    if (!mounted) return;
    final word = await _wordAtContextMenu();
    if (word == null || word.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showInfoDatoModal(context, word, widget.ambiente);
      }
    });
  }

  /// Abre la ventana de usos del procedimiento dinámico activo
  /// (tabla + columna donde se referencia).
  Future<void> _showUsosProcedimiento() async {
    if (!mounted) return;
    final activeProc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == _activeProcId,
      orElse: () => widget.procedimiento,
    );
    final cd = activeProc.cdProcedimiento;
    if (cd.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showUsosProcedimientoModal(context, cd, widget.ambiente);
      }
    });
  }

  /// Abre la ventana de ejecución del procedimiento dinámico activo.
  ///
  /// Es exclusiva de los procedimientos dinámicos: arma el contexto Oracle a
  /// partir de los identificadores que carga el usuario y muestra el resultado.
  ///
  /// Como se abre desde el editor, se ejecuta el **código actual del editor**
  /// (endpoint `ejecutar-borrador`), no el texto guardado en la base.
  Future<void> _ejecutarProcedimiento() async {
    if (!mounted) return;
    final activeProc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == _activeProcId,
      orElse: () => widget.procedimiento,
    );
    final cd = activeProc.cdProcedimiento;
    if (cd.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showEjecutarProcedimientoModal(
          context,
          cd,
          widget.ambiente,
          inConfiguracion: activeProc.inConfiguracion,
          obtenerTexto: () async =>
              await _withCtrl((ctrl) => ctrl.document.getText()) ??
              activeProc.deTexto,
        );
      }
    });
  }

  Future<void> _openDiff() async {
    final activeProc = _openProcs.firstWhere(
      (p) => p.cdProcedimiento == _activeProcId,
      orElse: () => widget.procedimiento,
    );
    final current = await _withCtrl((ctrl) => ctrl.document.getText());
    if (current == null || !mounted) return;
    await showProcedureDiff(
      context,
      title: 'Diff — ${activeProc.cdProcedimiento}',
      original: activeProc.deTexto,
      modified: current,
      language: activeProc.inConfiguracion == 'J' ? 'javascript' : 'sql',
    );
  }
}
