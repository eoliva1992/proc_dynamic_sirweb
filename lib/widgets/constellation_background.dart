import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Fondo animado de "constelación": estrellas en movimiento lento que se unen
/// con líneas cuando están lo bastante cerca.
///
/// Es **escalable**: la cantidad de estrellas se calcula a partir de la
/// superficie real disponible (`density` estrellas por cada 10.000 px²), de
/// modo que se ve igual de poblado en una ventana pequeña o en un monitor 4K.
/// El tamaño de estrellas y el radio de enlace se multiplican por [scale].
///
/// Uso típico (fondo a pantalla completa detrás del contenido):
/// ```dart
/// Stack(
///   children: [
///     const Positioned.fill(child: ConstellationBackground()),
///     Scaffold(backgroundColor: Colors.transparent, body: ...),
///   ],
/// )
/// ```
class ConstellationBackground extends StatefulWidget {
  const ConstellationBackground({
    super.key,
    this.density = 0.9,
    this.maxStars = 260,
    this.scale = 1.0,
    this.speed = 1.0,
    this.linkDistance = 130,
    this.starColor,
    this.lineColor,
    this.backgroundColor,
    this.backgroundGradient,
    this.parallax = true,
    this.parallaxStrength = 14,
    this.enabled = true,
    this.child,
  });

  /// Estrellas por cada 10.000 px² de superficie.
  final double density;

  /// Tope de estrellas (protege el rendimiento en pantallas enormes).
  final int maxStars;

  /// Multiplicador de tamaño de estrella y radio de enlace.
  final double scale;

  /// Multiplicador de velocidad de desplazamiento.
  final double speed;

  /// Distancia base (px lógicos, antes de [scale]) para dibujar una línea.
  final double linkDistance;

  /// Color de las estrellas. Por defecto deriva del [ColorScheme].
  final Color? starColor;

  /// Color de las líneas. Por defecto deriva del [ColorScheme.primary].
  final Color? lineColor;

  /// Color sólido de fondo. Ignorado si se pasa [backgroundGradient].
  final Color? backgroundColor;

  /// Degradado de fondo opcional.
  final Gradient? backgroundGradient;

  /// Desplaza suavemente la constelación siguiendo el puntero.
  final bool parallax;

  /// Amplitud máxima del parallax en píxeles.
  final double parallaxStrength;

  /// Si es `false` se dibuja el fondo estático (sin ticker). Útil para
  /// respetar `MediaQuery.disableAnimations` o modo de bajo consumo.
  final bool enabled;

  /// Contenido a dibujar por encima del fondo.
  final Widget? child;

  @override
  State<ConstellationBackground> createState() =>
      _ConstellationBackgroundState();
}

class _ConstellationBackgroundState extends State<ConstellationBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _stars = <_Star>[];
  final _rnd = math.Random(20260906);

  Size _size = Size.zero;
  Duration _last = Duration.zero;
  double _t = 0;
  Offset _pointer = Offset.zero; // -1..1 normalizado
  Offset _pointerEased = Offset.zero;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respeta "reducir movimiento" del sistema operativo.
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ConstellationBackground old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled) _syncTicker();
    if (widget.density != old.density || widget.maxStars != old.maxStars) {
      _rebuild(_size, force: true);
    }
  }

  /// En tests de widget una animación infinita hace que `pumpAndSettle`
  /// nunca termine; ahí se dibuja un único frame estático.
  static bool get _inWidgetTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  bool get _shouldAnimate => widget.enabled && !_reduceMotion && !_inWidgetTest;

  void _syncTicker() {
    if (_shouldAnimate) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtRaw = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // Clamp para evitar saltos tras un frame perdido / app en background.
    final dt = dtRaw.clamp(0.0, 1 / 30);
    _t += dt;

    if (_size.isEmpty) return;

    for (final s in _stars) {
      s.x += s.vx * dt * widget.speed;
      s.y += s.vy * dt * widget.speed;
      // Wrap-around toroidal en espacio normalizado.
      if (s.x < -0.02) s.x = 1.02;
      if (s.x > 1.02) s.x = -0.02;
      if (s.y < -0.02) s.y = 1.02;
      if (s.y > 1.02) s.y = -0.02;
    }

    // Suavizado del parallax.
    _pointerEased += (_pointer - _pointerEased) * (dt * 4).clamp(0.0, 1.0);
    setState(() {});
  }

  int _targetCount(Size size) {
    final area = size.width * size.height;
    final n = (area / 10000 * widget.density).round();
    return n.clamp(12, widget.maxStars);
  }

  void _rebuild(Size size, {bool force = false}) {
    if (size.isEmpty) return;
    final target = _targetCount(size);
    if (!force && target == _stars.length && size == _size) return;
    _size = size;

    if (_stars.length > target) {
      _stars.removeRange(target, _stars.length);
    } else {
      while (_stars.length < target) {
        _stars.add(_Star.random(_rnd));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final starColor =
        widget.starColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.75)
            : cs.onSurface.withValues(alpha: 0.45));
    final lineColor =
        widget.lineColor ?? cs.primary.withValues(alpha: isDark ? 0.35 : 0.28);

    Widget painter = LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        // Se reconstruye fuera de la fase de layout para no llamar setState.
        _rebuild(size);

        return RepaintBoundary(
          child: CustomPaint(
            painter: _ConstellationPainter(
              stars: _stars,
              time: _t,
              scale: widget.scale,
              linkDistance: widget.linkDistance * widget.scale,
              starColor: starColor,
              lineColor: lineColor,
              backgroundColor:
                  widget.backgroundColor ??
                  (widget.backgroundGradient == null
                      ? Theme.of(context).scaffoldBackgroundColor
                      : null),
              gradient: widget.backgroundGradient,
              parallax: widget.parallax
                  ? _pointerEased * widget.parallaxStrength
                  : Offset.zero,
            ),
            size: Size.infinite,
            child: widget.child,
          ),
        );
      },
    );

    if (widget.parallax) {
      painter = MouseRegion(
        opaque: false,
        onHover: (e) {
          if (_size.isEmpty) return;
          _pointer = Offset(
            (e.localPosition.dx / _size.width) * 2 - 1,
            (e.localPosition.dy / _size.height) * 2 - 1,
          );
        },
        onExit: (_) => _pointer = Offset.zero,
        child: painter,
      );
    }
    return painter;
  }
}

/// Cabecera reutilizable con una constelación animada por detrás del título.
///
/// Pensada para los encabezados de diálogos, modales, sheets y barras de
/// título. Mantiene el [decoration] original del contenedor y sólo agrega la
/// capa de estrellas entre el fondo y el [child].
///
/// ```dart
/// ConstellationHeader(
///   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
///   decoration: const BoxDecoration(gradient: LinearGradient(...)),
///   onDark: true,
///   child: Row(children: [...]),
/// )
/// ```
class ConstellationHeader extends StatelessWidget {
  const ConstellationHeader({
    super.key,
    required this.child,
    this.decoration,
    this.padding,
    this.height,
    this.width,
    this.borderRadius,
    this.density = 2.4,
    this.scale = 0.7,
    this.speed = 0.5,
    this.linkDistance = 95,
    this.starColor,
    this.lineColor,
    this.onDark,
  });

  final Widget child;
  final Decoration? decoration;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final double density;
  final double scale;
  final double speed;
  final double linkDistance;
  final Color? starColor;
  final Color? lineColor;

  /// `true` si la cabecera tiene fondo oscuro (estrellas claras).
  /// Si se omite se deduce del brillo del tema.
  final bool? onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: width,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ConstellationBackground(
                  density: density,
                  scale: scale,
                  speed: speed,
                  linkDistance: linkDistance,
                  backgroundColor: Colors.transparent,
                  starColor:
                      starColor ??
                      (dark
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.28)),
                  lineColor:
                      lineColor ??
                      (dark
                          ? Colors.white.withValues(alpha: 0.28)
                          : const Color(0xFF0078D4).withValues(alpha: 0.3)),
                  parallax: false,
                ),
              ),
            ),
            Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ],
        ),
      ),
    );
  }
}

/// Fondo de constelación listo para usar en el `flexibleSpace` de un [AppBar].
///
/// ```dart
/// AppBar(
///   backgroundColor: bg.withValues(alpha: 0.55),
///   flexibleSpace: const ConstellationAppBarBackground(),
///   title: ...,
/// )
/// ```
class ConstellationAppBarBackground extends StatelessWidget {
  const ConstellationAppBarBackground({
    super.key,
    this.blur = 6,
    this.density = 2.2,
    this.scale = 0.75,
    this.speed = 0.6,
    this.linkDistance = 90,
    this.starColor,
    this.lineColor,
  });

  final double blur;
  final double density;
  final double scale;
  final double speed;
  final double linkDistance;
  final Color? starColor;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: IgnorePointer(
          child: ConstellationBackground(
            density: density,
            scale: scale,
            speed: speed,
            linkDistance: linkDistance,
            backgroundColor: Colors.transparent,
            starColor: starColor ?? Colors.white.withValues(alpha: 0.75),
            lineColor:
                lineColor ?? const Color(0xFF4FC3F7).withValues(alpha: 0.4),
            parallax: false,
          ),
        ),
      ),
    );
  }
}

/// Título con constelación para `AlertDialog`.
///
/// Úsalo junto con `titlePadding: EdgeInsets.zero` para que la banda de
/// estrellas ocupe todo el ancho del diálogo:
///
/// ```dart
/// AlertDialog(
///   titlePadding: EdgeInsets.zero,
///   title: const ConstellationDialogTitle(child: Text('Título')),
///   ...
/// )
/// ```
class ConstellationDialogTitle extends StatelessWidget {
  const ConstellationDialogTitle({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 14),
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(28)),
    this.showDivider = true,
    this.starColor,
    this.lineColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool showDivider;
  final Color? starColor;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstellationHeader(
      width: double.infinity,
      padding: padding,
      borderRadius: borderRadius,
      starColor: starColor,
      lineColor: lineColor,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: showDivider
            ? Border(bottom: BorderSide(color: cs.outlineVariant))
            : null,
      ),
      child: DefaultTextStyle.merge(
        style:
            Theme.of(context).dialogTheme.titleTextStyle ??
            Theme.of(context).textTheme.titleLarge,
        child: child,
      ),
    );
  }
}

class _Star {
  _Star(this.x, this.y, this.vx, this.vy, this.radius, this.phase);

  double x; // 0..1
  double y; // 0..1
  double vx; // unidades normalizadas / segundo
  double vy;
  final double radius; // px lógicos base
  final double phase; // desfase del parpadeo

  factory _Star.random(math.Random r) => _Star(
    r.nextDouble(),
    r.nextDouble(),
    (r.nextDouble() - 0.5) * 0.02,
    (r.nextDouble() - 0.5) * 0.02,
    0.6 + r.nextDouble() * 1.6,
    r.nextDouble() * math.pi * 2,
  );
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.stars,
    required this.time,
    required this.scale,
    required this.linkDistance,
    required this.starColor,
    required this.lineColor,
    required this.backgroundColor,
    required this.gradient,
    required this.parallax,
  });

  final List<_Star> stars;
  final double time;
  final double scale;
  final double linkDistance;
  final Color starColor;
  final Color lineColor;
  final Color? backgroundColor;
  final Gradient? gradient;
  final Offset parallax;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    if (gradient != null) {
      canvas.drawRect(rect, Paint()..shader = gradient!.createShader(rect));
    } else if (backgroundColor != null) {
      canvas.drawRect(rect, Paint()..color = backgroundColor!);
    }

    // Posiciones en píxeles (con parallax aplicado).
    final pts = List<Offset>.generate(
      stars.length,
      (i) => Offset(
        stars[i].x * size.width + parallax.dx,
        stars[i].y * size.height + parallax.dy,
      ),
      growable: false,
    );

    // ── Líneas (grid espacial para evitar O(n²) puro) ─────────────────────
    final cell = math.max(linkDistance, 1.0);
    final cols = (size.width / cell).ceil() + 1;
    final buckets = <int, List<int>>{};
    for (var i = 0; i < pts.length; i++) {
      final cx = (pts[i].dx / cell).floor();
      final cy = (pts[i].dy / cell).floor();
      buckets.putIfAbsent(cy * cols + cx, () => <int>[]).add(i);
    }

    final linePaint = Paint()
      ..strokeWidth = math.max(0.5, 0.6 * scale)
      ..style = PaintingStyle.stroke;
    final maxD2 = linkDistance * linkDistance;

    for (var i = 0; i < pts.length; i++) {
      final cx = (pts[i].dx / cell).floor();
      final cy = (pts[i].dy / cell).floor();
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final list = buckets[(cy + dy) * cols + (cx + dx)];
          if (list == null) continue;
          for (final j in list) {
            if (j <= i) continue;
            final d2 = (pts[i] - pts[j]).distanceSquared;
            if (d2 > maxD2) continue;
            final f = 1 - math.sqrt(d2) / linkDistance;
            linePaint.color = lineColor.withValues(alpha: lineColor.a * f * f);
            canvas.drawLine(pts[i], pts[j], linePaint);
          }
        }
      }
    }

    // ── Estrellas ─────────────────────────────────────────────────────────
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < pts.length; i++) {
      final s = stars[i];
      final twinkle = 0.65 + 0.35 * math.sin(time * 1.6 + s.phase);
      dotPaint.color = starColor.withValues(alpha: starColor.a * twinkle);
      canvas.drawCircle(pts[i], s.radius * scale, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.time != time ||
      old.scale != scale ||
      old.linkDistance != linkDistance ||
      old.starColor != starColor ||
      old.lineColor != lineColor ||
      old.backgroundColor != backgroundColor ||
      old.parallax != parallax ||
      old.stars.length != stars.length;

  @override
  bool hitTest(ui.Offset position) => false;
}
