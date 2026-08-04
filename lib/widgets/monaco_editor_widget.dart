import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

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
  final List<Future<void> Function(fm.MonacoController)> _pending = [];

  void attach(fm.MonacoController ctrl) {
    _ctrl = ctrl;
    _ready = true;
    for (final cmd in _pending) {
      cmd(ctrl);
    }
    _pending.clear();
  }

  void _enqueue(Future<void> Function(fm.MonacoController) cmd) {
    if (_ready && _ctrl != null) {
      cmd(_ctrl!);
    } else {
      _pending.add(cmd);
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

  void clearContent() {
    _enqueue((ctrl) async => ctrl.document.setText(''));
  }

  // fm.MonacoEditor owns the controller lifecycle — only release the reference.
  void dispose() {
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
  final ValueChanged<String>? onChanged;
  final void Function(int line, int col)? onCursorChanged;
  final void Function(Object error, StackTrace stackTrace)? onError;

  const MonacoEditorWidget({
    super.key,
    required this.controller,
    required this.initialCode,
    this.language = 'plsql',
    this.darkTheme = true,
    this.onChanged,
    this.onCursorChanged,
    this.onError,
  });

  @override
  State<MonacoEditorWidget> createState() => _MonacoEditorWidgetState();
}

class _MonacoEditorWidgetState extends State<MonacoEditorWidget> {
  StreamSubscription<fm.Range?>? _selectionSub;

  fm.EditorOptions get _editorOptions => fm.EditorOptions(
    language: widget.language == 'javascript'
        ? fm.MonacoLanguage.javascript
        : fm.MonacoLanguage.sql,
    theme: widget.darkTheme ? fm.MonacoTheme.vsDark : fm.MonacoTheme.vs,
    fontSize: 14,
    minimap: const fm.MonacoMinimapOptions(enabled: true),
    wordWrap: fm.MonacoWordWrap.off,
    lineNumbers: fm.MonacoLineNumbers.on,
    renderWhitespace: fm.RenderWhitespace.none,
    tabSize: 2,
  );

  void _onReady(fm.MonacoController ctrl) {
    widget.controller.attach(ctrl);
    _selectionSub = ctrl.onSelectionChanged.listen((range) {
      if (range != null) {
        widget.onCursorChanged?.call(range.startLine, range.startColumn);
      }
    });
  }

  @override
  void didUpdateWidget(MonacoEditorWidget old) {
    super.didUpdateWidget(old);
    if (old.language != widget.language) {
      widget.controller.setLanguage(widget.language);
    }
  }

  @override
  void dispose() {
    _selectionSub?.cancel();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return fm.MonacoEditor(
      initialText: widget.initialCode,
      options: _editorOptions,
      contentDebounce: const Duration(milliseconds: 400),
      onReady: _onReady,
      onContentChanged: widget.onChanged,
      onError: widget.onError,
    );
  }
}
