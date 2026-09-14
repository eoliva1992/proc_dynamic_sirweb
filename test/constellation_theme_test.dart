import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/main.dart';
import 'package:proc_dynamic_sirweb/widgets/constellation_background.dart';
import 'package:proc_dynamic_sirweb/widgets/_editor_themes.dart';

/// La constelación debe "pertenecer" al tema activo: las estrellas se tiñen
/// con los acentos de la paleta y contrastan con el fondo.
void main() {
  test('las estrellas usan un color por acento del tema', () {
    const accents = [Color(0xFFFF7EDB), Color(0xFF36F9F6), Color(0xFFFEDE5D)];
    final stars = ConstellationColors.stars(accents: accents, onDark: true);

    expect(stars, hasLength(accents.length));
    // Cada estrella conserva el tono de su acento (no se colapsa a blanco).
    expect(stars.map((c) => c.toARGB32()).toSet(), hasLength(3));
    for (var i = 0; i < accents.length; i++) {
      expect(
        stars[i].r,
        closeTo(_lightened(accents[i]).r, 0.001),
        reason: 'la estrella $i perdió el tono de su acento',
      );
    }
  });

  test('los acentos se aclaran en oscuro y se profundizan en claro', () {
    const accent = Color(0xFF0078D4);
    final onDark = ConstellationColors.legible(accent, onDark: true);
    final onLight = ConstellationColors.legible(accent, onDark: false);

    expect(onDark.computeLuminance(), greaterThan(accent.computeLuminance()));
    expect(onLight.computeLuminance(), lessThan(accent.computeLuminance()));
  });

  test('la intensidad escala la opacidad sin desbordar', () {
    const accents = [Color(0xFF0078D4)];
    final normal = ConstellationColors.stars(accents: accents, onDark: true);
    final fuerte = ConstellationColors.stars(
      accents: accents,
      onDark: true,
      intensity: 5,
    );

    expect(fuerte.first.a, greaterThan(normal.first.a));
    expect(fuerte.first.a, lessThanOrEqualTo(1.0));
  });

  test('las estrellas son más opacas que las líneas en todos los temas', () {
    for (final t in kEditorThemes) {
      final cs = ProcDynamicApp.buildThemeFor(t.id).colorScheme;
      final stars = ConstellationColors.stars(
        accents: [cs.primary, cs.secondary, cs.tertiary],
        onDark: t.isDark,
      );
      final line = ConstellationColors.line(
        accent: cs.primary,
        onDark: t.isDark,
      );

      expect(
        stars.first.a,
        greaterThan(line.a),
        reason: 'en ${t.id} las estrellas no destacan sobre las líneas',
      );
    }
  });

  test('la constelación se mantiene sutil: es fondo, no contenido', () {
    for (final onDark in [true, false]) {
      final stars = ConstellationColors.stars(
        accents: const [Color(0xFF0078D4)],
        onDark: onDark,
      );
      final line = ConstellationColors.line(
        accent: const Color(0xFF0078D4),
        onDark: onDark,
      );
      // Techos de opacidad: si alguien vuelve a subirlos, este test avisa.
      expect(stars.first.a, lessThanOrEqualTo(0.55));
      expect(line.a, lessThanOrEqualTo(0.3));
    }
  });

  testWidgets('la constelación se repinta al cambiar de tema', (tester) async {
    Future<void> pumpWith(String themeId) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ProcDynamicApp.buildThemeFor(themeId),
          home: const Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: ConstellationBackground(parallax: false),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWith('synthwave-84');
    final synthwave = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<CustomPainter>()
        .length;
    expect(synthwave, greaterThan(0));

    await pumpWith('github-light');
    expect(tester.takeException(), isNull);
  });
}

/// Réplica local del aclarado que aplica [ConstellationColors.legible].
Color _lightened(Color c) => Color.lerp(c, Colors.white, 0.16)!;
