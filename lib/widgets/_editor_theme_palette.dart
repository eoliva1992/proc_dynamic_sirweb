import 'package:flutter/material.dart';

/// Paleta Material de un tema de la aplicación.
///
/// Es la fuente de verdad para construir el [ThemeData] de Flutter: cada tema
/// del editor (Monaco) lleva asociada una de estas paletas para que el color
/// llegue a TODA la UI, no solo al área de código.
@immutable
class AppPalette {
  // Acentos
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color tertiary;

  // Superficies
  final Color scaffoldBg;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerLow;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  // Texto y bordes
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;

  // AppBar
  final Color appBarBg;
  final Color onAppBar;

  const AppPalette({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.tertiary,
    required this.scaffoldBg,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerLow,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.appBarBg,
    required this.onAppBar,
  });

  /// Construye una paleta completa a partir de un puñado de colores base.
  ///
  /// Los tonos intermedios (`surfaceContainerHigh/Highest`, `outlineVariant`,
  /// `onPrimary`, `onAppBar`) se derivan automáticamente salvo que se indiquen.
  factory AppPalette.from({
    required Color primary,
    required Color background,
    required Color surface,
    required Color elevated,
    required Color onSurface,
    required Color onSurfaceVariant,
    required Color outline,
    required bool isDark,
    Color? onPrimary,
    Color? secondary,
    Color? tertiary,
    Color? outlineVariant,
    Color? appBarBg,
    Color? onAppBar,
  }) {
    final bar =
        appBarBg ??
        (isDark
            ? Color.lerp(background, Colors.black, 0.35)!
            : Color.lerp(background, Colors.black, 0.07)!);
    return AppPalette(
      primary: primary,
      onPrimary: onPrimary ?? _contrastOn(primary),
      secondary: secondary ?? primary,
      tertiary: tertiary ?? secondary ?? primary,
      scaffoldBg: background,
      surface: surface,
      surfaceContainer: elevated,
      surfaceContainerLow: background,
      surfaceContainerHigh: Color.lerp(elevated, onSurface, 0.07)!,
      surfaceContainerHighest: Color.lerp(elevated, onSurface, 0.14)!,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant ?? Color.lerp(outline, background, 0.55)!,
      onAppBar: onAppBar ?? _contrastOn(bar),
      appBarBg: bar,
    );
  }

  /// Blanco o negro según cuál contraste mejor sobre [c].
  ///
  /// El umbral 0.179 es el punto WCAG donde el contraste con blanco y con
  /// negro se iguala: `(1.05 / (L + 0.05)) == ((L + 0.05) / 0.05)`.
  /// Usar 0.5 (el valor "intuitivo") deja texto blanco ilegible sobre
  /// naranjas y azules medios.
  static Color _contrastOn(Color c) =>
      c.computeLuminance() > 0.179 ? const Color(0xFF1A1A1A) : Colors.white;
}
