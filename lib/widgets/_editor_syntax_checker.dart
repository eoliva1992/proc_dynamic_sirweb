part of 'code_editor_panel.dart';

// ── Modelo y checker de errores de sintaxis ──────────────────────────────────────────────────────────────────────────

class _SyntaxError {
  final int line; // 1-based
  final int col; // 1-based
  final String message;
  const _SyntaxError({
    required this.line,
    required this.col,
    required this.message,
  });
}

// ── Indicador de errores en el gutter ──────────────────────────────────────────────────────────────────────────────────
// Usa un ValueNotifier para escuchar cambios directamente desde el RenderObject,
// sin depender de la cadena de reconstrucción de widgets de CodeEditor.

class _ErrorGutterIndicator extends LeafRenderObjectWidget {
  final ValueNotifier<List<_SyntaxError>> errorsNotifier;
  final CodeIndicatorValueNotifier notifier;

  const _ErrorGutterIndicator({
    required this.errorsNotifier,
    required this.notifier,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ErrorGutterRenderObject(
        errorsNotifier: errorsNotifier,
        notifier: notifier,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ErrorGutterRenderObject renderObject,
  ) {
    renderObject
      ..errorsNotifier = errorsNotifier
      ..notifier = notifier;
  }
}

class _ErrorGutterRenderObject extends RenderBox {
  ValueNotifier<List<_SyntaxError>> _errorsNotifier;
  CodeIndicatorValueNotifier _notifier;

  static const double _kWidth = 10.0;
  static const double _kDotRadius = 3.0;

  _ErrorGutterRenderObject({
    required this._errorsNotifier,
    required this._notifier,
  });

  set errorsNotifier(ValueNotifier<List<_SyntaxError>> value) {
    if (_errorsNotifier == value) return;
    if (attached) _errorsNotifier.removeListener(markNeedsPaint);
    _errorsNotifier = value;
    if (attached) _errorsNotifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set notifier(CodeIndicatorValueNotifier value) {
    if (_notifier == value) return;
    if (attached) _notifier.removeListener(markNeedsPaint);
    _notifier = value;
    if (attached) _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(covariant PipelineOwner owner) {
    _errorsNotifier.addListener(markNeedsPaint);
    _notifier.addListener(markNeedsPaint);
    super.attach(owner);
  }

  @override
  void detach() {
    _errorsNotifier.removeListener(markNeedsPaint);
    _notifier.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = Size(_kWidth, constraints.maxHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final value = _notifier.value;
    final errors = _errorsNotifier.value;
    if (value == null || errors.isEmpty) return;

    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
    );

    final paint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.fill;

    // With wordWrap: false, paragraph.index + 1 == 1-based line number
    final errorLineSet = errors.map((e) => e.line).toSet();

    for (final paragraph in value.paragraphs) {
      if (errorLineSet.contains(paragraph.index + 1)) {
        final cy =
            offset.dy + paragraph.offset.dy + paragraph.preferredLineHeight / 2;
        final cx = offset.dx + _kWidth / 2;
        canvas.drawCircle(Offset(cx, cy), _kDotRadius, paint);
      }
    }

    canvas.restore();
  }
}
