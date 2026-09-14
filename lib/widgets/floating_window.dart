import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../app_navigator.dart';

// ── Infraestructura de ventanas flotantes ────────────────────────────────────
//
// Versión pública (reutilizable fuera del editor) de la infraestructura que
// usan los modales de consulta del editor (`_editor_float_window.dart`).
//
// Las ventanas se insertan en el overlay raíz en vez de usar `showDialog`, por
// lo que NO hay barrera modal: se pueden mover con el cursor, redimensionar y
// minimizar dejando el resto de la app utilizable.

/// Resuelve el [OverlayState] donde insertar la ventana.
///
/// `Overlay.of()` busca un Overlay **ancestro**, por lo que falla si [context]
/// es el contexto del propio Overlay (p.ej. `rootDialogContext`). En ese caso
/// se recurre al overlay del Navigator raíz.
OverlayState? _resolveOverlay(BuildContext context) {
  // 1. El propio context puede ser el del Overlay (rootDialogContext).
  if (context is StatefulElement && context.state is OverlayState) {
    return context.state as OverlayState;
  }
  // 2. Overlay ancestro (raíz).
  final ancestor = Overlay.maybeOf(context, rootOverlay: true);
  if (ancestor != null) return ancestor;
  // 3. Último recurso: overlay del Navigator raíz de la app.
  return rootNavigatorKey.currentState?.overlay;
}

/// Inserta una ventana flotante en el overlay raíz.
///
/// [builder] recibe el callback para cerrarla. Devuelve ese mismo callback por
/// si el llamador necesita cerrarla programáticamente.
///
/// La ventana aparece y desaparece con la misma animación que el resto de los
/// modales de la app (fundido + escala, `easeOutCubic`); el cierre espera a que
/// termine la transición antes de quitarla del overlay.
VoidCallback showFloatingWindow(
  BuildContext context,
  Widget Function(VoidCallback close) builder, {
  bool animated = true,
  Color? barrierColor,
  bool barrierDismissible = false,
}) {
  final overlay = _resolveOverlay(context);
  if (overlay == null) {
    throw FlutterError(
      'No se encontró un Overlay para montar la ventana flotante. '
      'Verificá que la app tenga un MaterialApp/Navigator activo.',
    );
  }

  late OverlayEntry entry;
  var removed = false;
  final animKey = GlobalKey<_FloatingWindowAnimatorState>();

  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  void close() {
    if (removed) return;
    final anim = animKey.currentState;
    if (!animated || anim == null) {
      remove();
      return;
    }
    // Deja correr la animación de salida antes de quitar la entry.
    anim.reverse().whenComplete(remove);
  }

  // Sin `Material` envolvente de pantalla completa: cada ventana pone el suyo
  // sobre su propio rectángulo. Así el resto de la pantalla queda libre y los
  // clics llegan a la app y a las demás ventanas.
  // Se envuelve la ventana en un `Overlay` local:
  // Así los menús contextuales, popups y dropdowns abiertos desde ella
  // se dibujan en este Overlay interno y quedan GARANTIZADAMENTE por delante
  // del marco y contenido de la ventana flotante.
  entry = OverlayEntry(
    builder: (_) => Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => animated
              ? _FloatingWindowAnimator(
                  key: animKey,
                  barrierColor: barrierColor,
                  onBarrierTap: barrierDismissible ? close : null,
                  child: builder(close),
                )
              : builder(close),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return close;
}

/// Aplica la transición de entrada/salida de las ventanas flotantes.
///
/// Replica la del resto de los modales de la app (ver `showObjectDetails`):
/// fundido + escala de 0.94 a 1 con `easeOutCubic`.
///
/// La barrera opcional sólo se funde (no escala) para que nunca deje bordes
/// sin cubrir durante la animación.
class _FloatingWindowAnimator extends StatefulWidget {
  const _FloatingWindowAnimator({
    super.key,
    required this.child,
    this.barrierColor,
    this.onBarrierTap,
  });

  final Widget child;
  final Color? barrierColor;
  final VoidCallback? onBarrierTap;

  @override
  State<_FloatingWindowAnimator> createState() =>
      _FloatingWindowAnimatorState();
}

class _FloatingWindowAnimatorState extends State<_FloatingWindowAnimator>
    with SingleTickerProviderStateMixin {
  static const _kDuration = Duration(milliseconds: 220);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _kDuration,
    reverseDuration: const Duration(milliseconds: 140),
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  /// Corre la animación de salida. El futuro completa al terminar.
  Future<void> reverse() => _ctrl.reverse();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = FadeTransition(
      opacity: _curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(_curved),
        child: widget.child,
      ),
    );
    final barrier = widget.barrierColor;
    if (barrier == null) return content;
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _curved,
            child: GestureDetector(
              onTap: widget.onBarrierTap,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(color: barrier),
            ),
          ),
        ),
        content,
      ],
    );
  }
}

// ── Diálogos sobre ventanas flotantes ────────────────────────────────────────
//
// `showDialog` monta una ruta en el Navigator, que queda POR DEBAJO de las
// entries del overlay raíz donde viven las ventanas flotantes: el diálogo
// quedaría tapado por la ventana que lo abrió. `showFloatingDialog` lo monta
// como una entry más del overlay, por lo que siempre queda por encima.

/// Muestra [builder] como diálogo modal por encima de las ventanas flotantes.
///
/// [builder] recibe el `close` con el que resolver el futuro:
/// `close(true)` / `close()`. Si se descarta con la barrera o con `Esc`, el
/// futuro completa con `null`.
Future<T?> showFloatingDialog<T>(
  BuildContext context,
  Widget Function(BuildContext context, void Function([T? result]) close)
  builder, {
  Color barrierColor = const Color(0x8A000000),
  bool barrierDismissible = true,
}) {
  final completer = Completer<T?>();
  late final VoidCallback closeWindow;
  var closed = false;

  void finish([T? result]) {
    if (!completer.isCompleted) completer.complete(result);
    if (closed) return;
    closed = true;
    closeWindow();
  }

  closeWindow = showFloatingWindow(
    context,
    (_) => _FloatingDialogLayer<T>(
      // Descarte por barrera: la entry se remueve sin pasar por `finish`.
      onDisposed: () {
        if (!completer.isCompleted) completer.complete(null);
      },
      onEscape: barrierDismissible ? finish : null,
      builder: builder,
      close: finish,
    ),
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
  );

  return completer.future;
}

class _FloatingDialogLayer<T> extends StatefulWidget {
  const _FloatingDialogLayer({
    required this.builder,
    required this.close,
    required this.onDisposed,
    this.onEscape,
  });

  final Widget Function(BuildContext context, void Function([T? result]) close)
  builder;
  final void Function([T? result]) close;
  final VoidCallback onDisposed;
  final VoidCallback? onEscape;

  @override
  State<_FloatingDialogLayer<T>> createState() =>
      _FloatingDialogLayerState<T>();
}

class _FloatingDialogLayerState<T> extends State<_FloatingDialogLayer<T>> {
  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onEscape = widget.onEscape;
    Widget child = Center(
      child: Builder(builder: (ctx) => widget.builder(ctx, widget.close)),
    );
    if (onEscape != null) {
      child = CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape},
        child: Focus(autofocus: true, child: child),
      );
    }
    return child;
  }
}

/// Reparte posiciones para las ventanas minimizadas, de modo que no se
/// superpongan entre sí (se apilan como una barra de tareas).
class FloatingWindowSlots {
  static final Set<int> _used = <int>{};

  /// Ancho y alto de una ventana minimizada.
  static const double barW = 300;
  static const double barH = 44;
  static const double _gap = 8;
  static const double _margin = 12;

  static int take() {
    var i = 0;
    while (_used.contains(i)) {
      i++;
    }
    _used.add(i);
    return i;
  }

  static void release(int? slot) {
    if (slot != null) _used.remove(slot);
  }

  /// Posición (left, top) de la ventana minimizada [slot] en pantalla.
  static (double, double) offsetFor(int slot, Size screen) {
    final perRow = ((screen.width - _margin * 2) / (barW + _gap)).floor().clamp(
      1,
      12,
    );
    final col = slot % perRow;
    final row = slot ~/ perRow;
    final left = _margin + col * (barW + _gap);
    final top = screen.height - _margin - barH - row * (barH + _gap);
    return (
      left.clamp(0.0, (screen.width - barW).clamp(0.0, double.infinity)),
      top.clamp(0.0, (screen.height - barH).clamp(0.0, double.infinity)),
    );
  }
}

/// Dibuja el clásico grip de 3 puntos en la esquina inferior derecha.
class WindowGripPainter extends CustomPainter {
  final Color color;
  const WindowGripPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const r = 2.0;
    const gap = 5.0;
    for (var i = 0; i < 3; i++) {
      final offset = Offset(
        size.width - gap * i - r,
        size.height - gap * i - r,
      );
      canvas.drawCircle(offset, r, paint);
    }
  }

  @override
  bool shouldRepaint(WindowGripPainter old) => old.color != color;
}

/// Botón de control de ventana (cerrar / minimizar / maximizar) con el mismo
/// look de los headers de la app.
///
/// Por defecto es un botón compacto con esquinas redondeadas. Para una barra de
/// título "nativa" (botones pegados al borde y ocupando todo el alto) usar
/// [WindowButton.titleBar].
class WindowButton extends StatefulWidget {
  const WindowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
    this.size = 14,
    this.width = 26,
    this.height = 26,
    this.radius = 5,
  });

  /// Variante para barra de título: ocupa todo el alto disponible y no tiene
  /// esquinas redondeadas, de modo que se pega al borde de la ventana.
  const WindowButton.titleBar({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
    this.size = 15,
    this.width = 44,
  }) : height = double.infinity,
       radius = 0;

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;
  final double size;
  final double width;
  final double height;
  final double radius;

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor = widget.isClose
        ? const Color(0xFFE81123)
        : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0));
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: widget.width,
      height: widget.height.isFinite ? widget.height : null,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _hovered ? hoverColor : Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: Icon(
        widget.icon,
        size: widget.size,
        color: _hovered && widget.isClose
            ? Colors.white
            : (isDark ? Colors.white70 : Colors.black54),
      ),
    );
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          // En la variante de barra de título el botón se estira al alto del
          // header para que el hover llegue hasta el borde superior.
          child: widget.height.isFinite
              ? button
              : SizedBox(
                  width: widget.width,
                  height: double.infinity,
                  child: button,
                ),
        ),
      ),
    );
  }
}
