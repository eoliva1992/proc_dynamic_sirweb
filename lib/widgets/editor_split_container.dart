import 'package:flutter/material.dart';

/// Modo de división del editor.
enum EditorSplitMode {
  /// Un solo editor (sin división).
  none,

  /// Dos editores divididos verticalmente (lado a lado / izquierda y derecha).
  vertical,

  /// Dos editores divididos horizontalmente (arriba y abajo).
  horizontal,
}

/// Contenedor reutilizable para albergar dos vistas de editor con un divisor
/// arrastrable (splitter) que permite cambiar la proporción entre ambos.
class EditorSplitContainer extends StatefulWidget {
  const EditorSplitContainer({
    super.key,
    required this.splitMode,
    required this.primaryChild,
    this.secondaryChild,
    this.secondaryBuilder,
    this.ratio = 0.5,
    this.onRatioChanged,
    this.minRatio = 0.15,
    this.maxRatio = 0.85,
    this.onCloseSecondary,
  }) : assert(
         secondaryChild != null ||
             secondaryBuilder != null ||
             splitMode == EditorSplitMode.none,
         'Either secondaryChild or secondaryBuilder must be provided when splitMode is not none',
       );

  /// Modo actual de división.
  final EditorSplitMode splitMode;

  /// Vista principal del editor.
  final Widget primaryChild;

  /// Vista secundaria (clon o split) del editor.
  final Widget? secondaryChild;

  /// Builder perezoso (lazy) para la vista secundaria.
  /// Solo se invoca cuando [splitMode] != [EditorSplitMode.none].
  final WidgetBuilder? secondaryBuilder;

  /// Proporción actual del panel principal (0.0 a 1.0).
  final double ratio;

  /// Callback emitido cuando el usuario arrastra el divisor.
  final ValueChanged<double>? onRatioChanged;

  /// Proporción mínima para el panel primario.
  final double minRatio;

  /// Proporción máxima para el panel primario.
  final double maxRatio;

  /// Callback para cerrar la vista secundaria (split).
  final VoidCallback? onCloseSecondary;

  @override
  State<EditorSplitContainer> createState() => _EditorSplitContainerState();
}

class _EditorSplitContainerState extends State<EditorSplitContainer> {
  late double _currentRatio;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentRatio = widget.ratio.clamp(widget.minRatio, widget.maxRatio);
  }

  @override
  void didUpdateWidget(EditorSplitContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ratio != widget.ratio && !_isDragging) {
      _currentRatio = widget.ratio.clamp(widget.minRatio, widget.maxRatio);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.splitMode == EditorSplitMode.none) {
      return widget.primaryChild;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final isVertical = widget.splitMode == EditorSplitMode.vertical;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = isVertical
            ? constraints.maxWidth
            : constraints.maxHeight;
        final dividerSize = 6.0;
        final availableSize = (totalSize - dividerSize).clamp(
          0.0,
          double.infinity,
        );

        final primarySize = (availableSize * _currentRatio).clamp(
          availableSize * widget.minRatio,
          availableSize * widget.maxRatio,
        );
        final secondarySize = (availableSize - primarySize).clamp(
          0.0,
          double.infinity,
        );

        final divider = MouseRegion(
          cursor: isVertical
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: isVertical
                ? (_) => setState(() => _isDragging = true)
                : null,
            onHorizontalDragUpdate: isVertical
                ? (details) {
                    if (availableSize <= 0) return;
                    setState(() {
                      final newRatio =
                          (_currentRatio + (details.delta.dx / availableSize))
                              .clamp(widget.minRatio, widget.maxRatio);
                      _currentRatio = newRatio;
                      widget.onRatioChanged?.call(newRatio);
                    });
                  }
                : null,
            onHorizontalDragEnd: isVertical
                ? (_) => setState(() => _isDragging = false)
                : null,
            onVerticalDragStart: !isVertical
                ? (_) => setState(() => _isDragging = true)
                : null,
            onVerticalDragUpdate: !isVertical
                ? (details) {
                    if (availableSize <= 0) return;
                    setState(() {
                      final newRatio =
                          (_currentRatio + (details.delta.dy / availableSize))
                              .clamp(widget.minRatio, widget.maxRatio);
                      _currentRatio = newRatio;
                      widget.onRatioChanged?.call(newRatio);
                    });
                  }
                : null,
            onVerticalDragEnd: !isVertical
                ? (_) => setState(() => _isDragging = false)
                : null,
            child: Container(
              width: isVertical ? dividerSize : double.infinity,
              height: isVertical ? double.infinity : dividerSize,
              color: _isDragging
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.5),
              child: Center(
                child: Container(
                  width: isVertical ? 2 : 24,
                  height: isVertical ? 24 : 2,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        );

        final resolvedSecondary = widget.secondaryBuilder != null
            ? widget.secondaryBuilder!(context)
            : (widget.secondaryChild ?? const SizedBox.shrink());

        final secondaryWrapper = Stack(
          children: [
            Positioned.fill(child: resolvedSecondary),
            if (widget.onCloseSecondary != null)
              Positioned(
                top: 6,
                right: 6,
                child: Tooltip(
                  message: 'Cerrar división (Ctrl+\\)',
                  child: InkWell(
                    onTap: widget.onCloseSecondary,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color:
                            (isDark
                                    ? cs.surfaceContainerHigh
                                    : cs.surfaceContainerHighest)
                                .withValues(alpha: 0.85),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.6),
                          width: 0.8,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

        if (isVertical) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: primarySize, child: widget.primaryChild),
              divider,
              SizedBox(width: secondarySize, child: secondaryWrapper),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: primarySize, child: widget.primaryChild),
              divider,
              SizedBox(height: secondarySize, child: secondaryWrapper),
            ],
          );
        }
      },
    );
  }
}
