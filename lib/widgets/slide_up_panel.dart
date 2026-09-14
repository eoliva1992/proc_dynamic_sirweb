import 'package:flutter/material.dart';

/// Panel que entra deslizándose desde abajo y se funde al salir.
///
/// Pensado para paneles flotantes anclados al borde inferior de un `Stack`
/// (p. ej. el panel de problemas del editor).
///
/// Dos decisiones importantes:
///
/// * **Se anima la posición, no la altura.** Animar la altura obligaría al
///   contenido (normalmente un `ListView`) a re-maquetarse en cada frame.
/// * **Cuando está oculto no se monta nada.** Así no pinta, no consume layout
///   y no intercepta clics sobre lo que haya debajo.
class SlideUpPanel extends StatelessWidget {
  const SlideUpPanel({
    super.key,
    required this.visible,
    required this.height,
    required this.child,
    this.showDuration = const Duration(milliseconds: 260),
    this.hideDuration = const Duration(milliseconds: 190),
  });

  /// Estado objetivo. Al cambiar, se anima la transición.
  final bool visible;

  /// Altura del panel; también es la distancia que recorre al deslizarse.
  final double height;

  final Widget child;
  final Duration showDuration;
  final Duration hideDuration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: visible ? 1 : 0),
      duration: visible ? showDuration : hideDuration,
      curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
      builder: (context, t, animatedChild) {
        if (t == 0) return const SizedBox.shrink();
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * height),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}
