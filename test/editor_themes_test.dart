import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/main.dart';
import 'package:proc_dynamic_sirweb/widgets/_editor_themes.dart';

/// Valida la integridad del catálogo unificado de temas: ids, pares
/// claro/oscuro, definiciones Monaco y construcción del ThemeData.
void main() {
  test('los ids de tema son únicos', () {
    final ids = kEditorThemes.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('cada pairId existe y tiene la luminosidad opuesta', () {
    for (final t in kEditorThemes) {
      final pairId = t.pairId;
      if (pairId == null) continue;
      final pair = kEditorThemeById[pairId];
      expect(pair, isNotNull, reason: '${t.id} apunta a un pairId inexistente');
      expect(
        pair!.isDark,
        isNot(t.isDark),
        reason: '${t.id} y $pairId tienen la misma luminosidad',
      );
      expect(
        pair.pairId,
        t.id,
        reason: 'el par ${t.id} ↔ $pairId no es simétrico',
      );
    }
  });

  test('solo los temas nativos de Monaco carecen de definición', () {
    const builtIn = {'vs', 'vs-dark', 'hc-black', 'hc-light'};
    for (final t in kEditorThemes) {
      if (builtIn.contains(t.id)) {
        expect(t.definition, isNull, reason: '${t.id} no debe redefinirse');
      } else {
        expect(t.definition, isNotNull, reason: '${t.id} necesita definición');
        expect(t.definition!.id, t.id);
      }
    }
  });

  test('buildThemeFor respeta la luminosidad declarada de cada tema', () {
    for (final t in kEditorThemes) {
      final theme = ProcDynamicApp.buildThemeFor(t.id);
      expect(
        theme.brightness,
        t.isDark ? Brightness.dark : Brightness.light,
        reason: 'brightness incorrecto en ${t.id}',
      );
      expect(theme.colorScheme.primary, t.palette.primary);
      expect(theme.scaffoldBackgroundColor, t.palette.scaffoldBg);
    }
  });

  test('un id desconocido cae en el tema por defecto', () {
    final fallback = ProcDynamicApp.buildThemeFor('no-existe');
    expect(fallback.colorScheme.primary, kEditorThemes.first.palette.primary);
  });

  test('la categoría Coloridos aporta temas claros y oscuros', () {
    final coloridos = kEditorThemes.where((t) => t.category == 'Coloridos');
    expect(coloridos.length, greaterThanOrEqualTo(10));
    expect(coloridos.any((t) => t.isDark), isTrue);
    expect(coloridos.any((t) => !t.isDark), isTrue);
  });

  test('groupedEditorThemes filtra por luminosidad', () {
    final claros = groupedEditorThemes(onlyDark: false);
    for (final entry in claros.entries) {
      for (final t in entry.value) {
        expect(t.isDark, isFalse);
      }
    }
    expect(groupedEditorThemes().length, greaterThanOrEqualTo(4));
  });

  test('el contenido de la AppBar contrasta con su fondo', () {
    for (final t in kEditorThemes) {
      final p = t.palette;
      expect(
        _contrastRatio(p.onAppBar, p.appBarBg),
        greaterThanOrEqualTo(4.5),
        reason: 'AppBar de ${t.id} sin contraste suficiente',
      );
    }
  });

  test('ningún tema claro arrastra una AppBar oscura de otro tema', () {
    // Los temas claros pueden tener barra de color saturado (categoría
    // Coloridos), pero nunca el gris oscuro heredado del modo dark.
    for (final t in kEditorThemes.where((t) => !t.isDark)) {
      expect(
        t.palette.appBarBg,
        isNot(const Color(0xFF2C2C2C)),
        reason: '${t.id} conserva la AppBar oscura por defecto',
      );
    }
  });
}

/// Ratio de contraste WCAG entre dos colores opacos.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}
