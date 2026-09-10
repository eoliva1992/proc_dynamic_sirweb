import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '_editor_oracle_theme.dart';
import '_editor_theme_defs.dart';
import '_editor_theme_palette.dart';

export '_editor_theme_palette.dart';

// ── Modelo unificado de tema ────────────────────────────────────────────────

/// Descripción completa de un tema: metadatos para el picker, paleta Material
/// para el [ThemeData] de Flutter y la definición Monaco para el editor.
///
/// Es la ÚNICA fuente de verdad: añadir un tema = añadir una entrada aquí.
@immutable
class EditorThemeMeta {
  /// Id compartido por Monaco y Flutter.
  final String id;
  final String name;

  /// Color de fondo, para la muestra del picker.
  final Color swatch;

  /// Color de acento, para la muestra del picker.
  final Color accent;
  final String category;
  final bool isDark;

  /// Tema equivalente en la luminosidad opuesta (botón de toggle claro/oscuro).
  final String? pairId;
  final AppPalette palette;

  /// `null` para los temas integrados en Monaco (vs, vs-dark, hc-black, hc-light).
  final MonacoThemeDefinition? definition;

  const EditorThemeMeta({
    required this.id,
    required this.name,
    required this.swatch,
    required this.accent,
    required this.category,
    required this.isDark,
    required this.palette,
    this.pairId,
    this.definition,
  });
}

// ── Catálogo ────────────────────────────────────────────────────────────────
//
// El orden importa: los pickers agrupan por `category` asumiendo que las
// entradas de una misma categoría son contiguas.

final kEditorThemes = <EditorThemeMeta>[
  // ── Oracle ────────────────────────────────────────────────────────────────
  EditorThemeMeta(
    id: 'oracle-dark',
    name: 'Oracle Dark',
    category: 'Oracle',
    isDark: true,
    pairId: 'oracle-light',
    swatch: const Color(0xFF1A1A2E),
    accent: const Color(0xFF0078D4),
    definition: oracleDark,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF0078D4),
      background: const Color(0xFF1E1E1E),
      surface: const Color(0xFF252526),
      elevated: const Color(0xFF252526),
      onSurface: const Color(0xFFD4D4D4),
      onSurfaceVariant: const Color(0xFF969696),
      outline: const Color(0xFF474747),
      outlineVariant: const Color(0xFF3C3C3C),
      appBarBg: const Color(0xFF323233),
    ),
  ),
  EditorThemeMeta(
    id: 'oracle-light',
    name: 'Oracle Light',
    category: 'Oracle',
    isDark: false,
    pairId: 'oracle-dark',
    swatch: const Color(0xFFFAFAFA),
    accent: const Color(0xFF0078D4),
    definition: oracleLight,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF0078D4),
      background: const Color(0xFFF5F5F5),
      surface: Colors.white,
      elevated: const Color(0xFFECECEC),
      onSurface: const Color(0xDD000000),
      onSurfaceVariant: const Color(0x73000000),
      outline: const Color(0xFFE0E0E0),
      outlineVariant: const Color(0xFFEEEEEE),
    ),
  ),

  // ── VS Code ───────────────────────────────────────────────────────────────
  EditorThemeMeta(
    id: 'vs-dark',
    name: 'VS Dark',
    category: 'VS Code',
    isDark: true,
    pairId: 'vs',
    swatch: const Color(0xFF1E1E1E),
    accent: const Color(0xFF0078D4),
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF0078D4),
      background: const Color(0xFF1E1E1E),
      surface: const Color(0xFF252526),
      elevated: const Color(0xFF252526),
      onSurface: const Color(0xFFD4D4D4),
      onSurfaceVariant: const Color(0xFF969696),
      outline: const Color(0xFF474747),
      outlineVariant: const Color(0xFF3C3C3C),
      appBarBg: const Color(0xFF323233),
    ),
  ),
  EditorThemeMeta(
    id: 'vs',
    name: 'VS Light',
    category: 'VS Code',
    isDark: false,
    pairId: 'vs-dark',
    swatch: const Color(0xFFFFFFFF),
    accent: const Color(0xFF0078D4),
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF0078D4),
      background: const Color(0xFFF5F5F5),
      surface: Colors.white,
      elevated: const Color(0xFFECECEC),
      onSurface: const Color(0xDD000000),
      onSurfaceVariant: const Color(0x73000000),
      outline: const Color(0xFFE0E0E0),
      outlineVariant: const Color(0xFFEEEEEE),
    ),
  ),
  EditorThemeMeta(
    id: 'hc-black',
    name: 'High Contrast Dark',
    category: 'VS Code',
    isDark: true,
    pairId: 'hc-light',
    swatch: const Color(0xFF000000),
    accent: Colors.white,
    palette: AppPalette.from(
      isDark: true,
      primary: Colors.white,
      onPrimary: Colors.black,
      background: Colors.black,
      surface: const Color(0xFF0A0A0A),
      elevated: const Color(0xFF111111),
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFC8C8C8),
      outline: const Color(0xFF6B6B6B),
      outlineVariant: const Color(0xFF3D3D3D),
      appBarBg: const Color(0xFF111111),
    ),
  ),
  EditorThemeMeta(
    id: 'hc-light',
    name: 'High Contrast Light',
    category: 'VS Code',
    isDark: false,
    pairId: 'hc-black',
    swatch: const Color(0xFFFFFFFF),
    accent: const Color(0xFF0000CC),
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF0000CC),
      background: Colors.white,
      surface: const Color(0xFFF5F5F5),
      elevated: const Color(0xFFEBEBEB),
      onSurface: Colors.black,
      onSurfaceVariant: const Color(0xFF3D3D3D),
      outline: const Color(0xFF767676),
      outlineVariant: const Color(0xFFABABAB),
      appBarBg: Colors.white,
      onAppBar: Colors.black,
    ),
  ),

  // ── Populares ─────────────────────────────────────────────────────────────
  EditorThemeMeta(
    id: 'monokai',
    name: 'Monokai',
    category: 'Populares',
    isDark: true,
    swatch: const Color(0xFF272822),
    accent: const Color(0xFFA6E22E),
    definition: monokaiDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFA6E22E),
      secondary: const Color(0xFFF92672),
      tertiary: const Color(0xFFE6DB74),
      background: const Color(0xFF272822),
      surface: const Color(0xFF2D2E27),
      elevated: const Color(0xFF32332C),
      onSurface: const Color(0xFFF8F8F2),
      onSurfaceVariant: const Color(0xFF90908A),
      outline: const Color(0xFF4E4D40),
      outlineVariant: const Color(0xFF3E3D32),
      appBarBg: const Color(0xFF1F1F1A),
    ),
  ),
  EditorThemeMeta(
    id: 'dracula',
    name: 'Dracula',
    category: 'Populares',
    isDark: true,
    swatch: const Color(0xFF282A36),
    accent: const Color(0xFFBD93F9),
    definition: draculaDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFBD93F9),
      secondary: const Color(0xFFFF79C6),
      tertiary: const Color(0xFF8BE9FD),
      background: const Color(0xFF282A36),
      surface: const Color(0xFF2E3045),
      elevated: const Color(0xFF32354A),
      onSurface: const Color(0xFFF8F8F2),
      onSurfaceVariant: const Color(0xFF6272A4),
      outline: const Color(0xFF44475A),
      outlineVariant: const Color(0xFF2E3045),
      appBarBg: const Color(0xFF1E1F29),
    ),
  ),
  EditorThemeMeta(
    id: 'solarized-dark',
    name: 'Solarized Dark',
    category: 'Populares',
    isDark: true,
    pairId: 'solarized-light',
    swatch: const Color(0xFF002B36),
    accent: const Color(0xFF268BD2),
    definition: solarizedDarkDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF268BD2),
      secondary: const Color(0xFF859900),
      tertiary: const Color(0xFF2AA198),
      background: const Color(0xFF002B36),
      surface: const Color(0xFF073642),
      elevated: const Color(0xFF0A3F4E),
      onSurface: const Color(0xFF839496),
      onSurfaceVariant: const Color(0xFF657B83),
      outline: const Color(0xFF2F5867),
      outlineVariant: const Color(0xFF1C4050),
      appBarBg: const Color(0xFF001C23),
    ),
  ),
  EditorThemeMeta(
    id: 'solarized-light',
    name: 'Solarized Light',
    category: 'Populares',
    isDark: false,
    pairId: 'solarized-dark',
    swatch: const Color(0xFFFDF6E3),
    accent: const Color(0xFF268BD2),
    definition: solarizedLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF268BD2),
      secondary: const Color(0xFF859900),
      tertiary: const Color(0xFF2AA198),
      background: const Color(0xFFEEE8D5),
      surface: const Color(0xFFFDF6E3),
      elevated: const Color(0xFFEDE5CF),
      onSurface: const Color(0xFF657B83),
      onSurfaceVariant: const Color(0xFF93A1A1),
      outline: const Color(0xFFC8BEAC),
      outlineVariant: const Color(0xFFD5CDB8),
      appBarBg: const Color(0xFFE8E1CB),
    ),
  ),
  EditorThemeMeta(
    id: 'one-dark',
    name: 'One Dark',
    category: 'Populares',
    isDark: true,
    pairId: 'one-light',
    swatch: const Color(0xFF282C34),
    accent: const Color(0xFF61AFEF),
    definition: oneDarkDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF61AFEF),
      secondary: const Color(0xFFC678DD),
      tertiary: const Color(0xFF98C379),
      background: const Color(0xFF21252B),
      surface: const Color(0xFF282C34),
      elevated: const Color(0xFF2C313A),
      onSurface: const Color(0xFFABB2BF),
      onSurfaceVariant: const Color(0xFF5C6370),
      outline: const Color(0xFF3E4451),
      outlineVariant: const Color(0xFF2C313A),
      appBarBg: const Color(0xFF1A1D23),
    ),
  ),
  EditorThemeMeta(
    id: 'one-light',
    name: 'One Light',
    category: 'Populares',
    isDark: false,
    pairId: 'one-dark',
    swatch: const Color(0xFFFAFAFA),
    accent: const Color(0xFF4078F2),
    definition: oneLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF4078F2),
      secondary: const Color(0xFFA626A4),
      tertiary: const Color(0xFF50A14F),
      background: const Color(0xFFF0F0F1),
      surface: const Color(0xFFFAFAFA),
      elevated: const Color(0xFFEAEAEB),
      onSurface: const Color(0xFF383A42),
      onSurfaceVariant: const Color(0xFF8C8C90),
      outline: const Color(0xFFD3D3D5),
      appBarBg: const Color(0xFFE7E7E8),
    ),
  ),
  EditorThemeMeta(
    id: 'nord',
    name: 'Nord',
    category: 'Populares',
    isDark: true,
    swatch: const Color(0xFF2E3440),
    accent: const Color(0xFF88C0D0),
    definition: nordDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF88C0D0),
      secondary: const Color(0xFF81A1C1),
      tertiary: const Color(0xFFA3BE8C),
      background: const Color(0xFF2E3440),
      surface: const Color(0xFF3B4252),
      elevated: const Color(0xFF434C5E),
      onSurface: const Color(0xFFECEFF4),
      onSurfaceVariant: const Color(0xFFD8DEE9),
      outline: const Color(0xFF4C566A),
      outlineVariant: const Color(0xFF434C5E),
      appBarBg: const Color(0xFF2C3346),
    ),
  ),
  EditorThemeMeta(
    id: 'tokyo-night',
    name: 'Tokyo Night',
    category: 'Populares',
    isDark: true,
    swatch: const Color(0xFF1A1B26),
    accent: const Color(0xFF7AA2F7),
    definition: tokyoNightDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF7AA2F7),
      secondary: const Color(0xFFBB9AF7),
      tertiary: const Color(0xFF9ECE6A),
      background: const Color(0xFF1A1B26),
      surface: const Color(0xFF24283B),
      elevated: const Color(0xFF2A2B3C),
      onSurface: const Color(0xFFC0CAF5),
      onSurfaceVariant: const Color(0xFF565F89),
      outline: const Color(0xFF3B4261),
      outlineVariant: const Color(0xFF2A2B3C),
      appBarBg: const Color(0xFF16161E),
    ),
  ),
  EditorThemeMeta(
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    category: 'Populares',
    isDark: true,
    pairId: 'catppuccin-latte',
    swatch: const Color(0xFF1E1E2E),
    accent: const Color(0xFFCBA6F7),
    definition: catppuccinMochaDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFCBA6F7),
      secondary: const Color(0xFF89B4FA),
      tertiary: const Color(0xFFA6E3A1),
      background: const Color(0xFF1E1E2E),
      surface: const Color(0xFF24273A),
      elevated: const Color(0xFF2A2B3C),
      onSurface: const Color(0xFFCDD6F4),
      onSurfaceVariant: const Color(0xFF6C7086),
      outline: const Color(0xFF45475A),
      outlineVariant: const Color(0xFF313244),
      appBarBg: const Color(0xFF181825),
    ),
  ),
  EditorThemeMeta(
    id: 'catppuccin-latte',
    name: 'Catppuccin Latte',
    category: 'Populares',
    isDark: false,
    pairId: 'catppuccin-mocha',
    swatch: const Color(0xFFEFF1F5),
    accent: const Color(0xFF8839EF),
    definition: catppuccinLatteDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF8839EF),
      secondary: const Color(0xFF1E66F5),
      tertiary: const Color(0xFF179299),
      background: const Color(0xFFEFF1F5),
      surface: const Color(0xFFFFFFFF),
      elevated: const Color(0xFFE6E9EF),
      onSurface: const Color(0xFF4C4F69),
      onSurfaceVariant: const Color(0xFF8C8FA1),
      outline: const Color(0xFFCCD0DA),
      appBarBg: const Color(0xFF1E66F5),
    ),
  ),
  EditorThemeMeta(
    id: 'gruvbox-dark',
    name: 'Gruvbox Dark',
    category: 'Populares',
    isDark: true,
    pairId: 'gruvbox-light',
    swatch: const Color(0xFF282828),
    accent: const Color(0xFFFABD2F),
    definition: gruvboxDarkDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFFABD2F),
      secondary: const Color(0xFFFB4934),
      tertiary: const Color(0xFFB8BB26),
      background: const Color(0xFF282828),
      surface: const Color(0xFF32302F),
      elevated: const Color(0xFF3C3836),
      onSurface: const Color(0xFFEBDBB2),
      onSurfaceVariant: const Color(0xFF928374),
      outline: const Color(0xFF504945),
      outlineVariant: const Color(0xFF3C3836),
      appBarBg: const Color(0xFF1D2021),
    ),
  ),
  EditorThemeMeta(
    id: 'gruvbox-light',
    name: 'Gruvbox Light',
    category: 'Populares',
    isDark: false,
    pairId: 'gruvbox-dark',
    swatch: const Color(0xFFFBF1C7),
    accent: const Color(0xFFB57614),
    definition: gruvboxLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFFB57614),
      secondary: const Color(0xFF9D0006),
      tertiary: const Color(0xFF79740E),
      background: const Color(0xFFF2E5BC),
      surface: const Color(0xFFFBF1C7),
      elevated: const Color(0xFFEBDBB2),
      onSurface: const Color(0xFF3C3836),
      onSurfaceVariant: const Color(0xFF7C6F64),
      outline: const Color(0xFFD5C4A1),
      appBarBg: const Color(0xFFEBDBB2),
    ),
  ),
  EditorThemeMeta(
    id: 'rose-pine-moon',
    name: 'Rosé Pine Moon',
    category: 'Populares',
    isDark: true,
    pairId: 'rose-pine-dawn',
    swatch: const Color(0xFF232136),
    accent: const Color(0xFFC4A7E7),
    definition: rosePineMoonDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFC4A7E7),
      secondary: const Color(0xFFEA9A97),
      tertiary: const Color(0xFF9CCFD8),
      background: const Color(0xFF232136),
      surface: const Color(0xFF2A273F),
      elevated: const Color(0xFF393552),
      onSurface: const Color(0xFFE0DEF4),
      onSurfaceVariant: const Color(0xFF908CAA),
      outline: const Color(0xFF44415A),
      outlineVariant: const Color(0xFF2A273F),
      appBarBg: const Color(0xFF1D1B2C),
    ),
  ),
  EditorThemeMeta(
    id: 'rose-pine-dawn',
    name: 'Rosé Pine Dawn',
    category: 'Populares',
    isDark: false,
    pairId: 'rose-pine-moon',
    swatch: const Color(0xFFFAF4ED),
    accent: const Color(0xFF907AA9),
    definition: rosePineDawnDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF907AA9),
      secondary: const Color(0xFFD7827E),
      tertiary: const Color(0xFF56949F),
      background: const Color(0xFFFAF4ED),
      surface: const Color(0xFFFFFAF3),
      elevated: const Color(0xFFF2E9E1),
      onSurface: const Color(0xFF575279),
      onSurfaceVariant: const Color(0xFF9893A5),
      outline: const Color(0xFFDFDAD9),
      appBarBg: const Color(0xFFF2E9E1),
    ),
  ),
  EditorThemeMeta(
    id: 'night-owl',
    name: 'Night Owl',
    category: 'Populares',
    isDark: true,
    pairId: 'light-owl',
    swatch: const Color(0xFF011627),
    accent: const Color(0xFF82AAFF),
    definition: nightOwlDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF82AAFF),
      secondary: const Color(0xFFC792EA),
      tertiary: const Color(0xFF7FDBCA),
      background: const Color(0xFF011627),
      surface: const Color(0xFF0B2942),
      elevated: const Color(0xFF10334F),
      onSurface: const Color(0xFFD6DEEB),
      onSurfaceVariant: const Color(0xFF637777),
      outline: const Color(0xFF1D3B53),
      outlineVariant: const Color(0xFF0B2942),
      appBarBg: const Color(0xFF010E1A),
    ),
  ),
  EditorThemeMeta(
    id: 'light-owl',
    name: 'Light Owl',
    category: 'Populares',
    isDark: false,
    pairId: 'night-owl',
    swatch: const Color(0xFFFBFBFB),
    accent: const Color(0xFF4876D6),
    definition: lightOwlDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF4876D6),
      secondary: const Color(0xFF994CC3),
      tertiary: const Color(0xFF0C969B),
      background: const Color(0xFFF0F0F0),
      surface: const Color(0xFFFBFBFB),
      elevated: const Color(0xFFE8E8E8),
      onSurface: const Color(0xFF403F53),
      onSurfaceVariant: const Color(0xFF989FB1),
      outline: const Color(0xFFD9D9D9),
      appBarBg: const Color(0xFFE8E8E8),
    ),
  ),
  EditorThemeMeta(
    id: 'kanagawa',
    name: 'Kanagawa',
    category: 'Populares',
    isDark: true,
    swatch: const Color(0xFF1F1F28),
    accent: const Color(0xFF7E9CD8),
    definition: kanagawaDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF7E9CD8),
      secondary: const Color(0xFFD27E99),
      tertiary: const Color(0xFF98BB6C),
      background: const Color(0xFF1F1F28),
      surface: const Color(0xFF2A2A37),
      elevated: const Color(0xFF363646),
      onSurface: const Color(0xFFDCD7BA),
      onSurfaceVariant: const Color(0xFF727169),
      outline: const Color(0xFF54546D),
      outlineVariant: const Color(0xFF363646),
      appBarBg: const Color(0xFF16161D),
    ),
  ),
  EditorThemeMeta(
    id: 'everforest-dark',
    name: 'Everforest Dark',
    category: 'Populares',
    isDark: true,
    pairId: 'everforest-light',
    swatch: const Color(0xFF2D353B),
    accent: const Color(0xFFA7C080),
    definition: everforestDarkDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFA7C080),
      secondary: const Color(0xFF7FBBB3),
      tertiary: const Color(0xFFDBBC7F),
      background: const Color(0xFF2D353B),
      surface: const Color(0xFF343F44),
      elevated: const Color(0xFF3D484D),
      onSurface: const Color(0xFFD3C6AA),
      onSurfaceVariant: const Color(0xFF859289),
      outline: const Color(0xFF475258),
      outlineVariant: const Color(0xFF343F44),
      appBarBg: const Color(0xFF232A2E),
    ),
  ),
  EditorThemeMeta(
    id: 'everforest-light',
    name: 'Everforest Light',
    category: 'Populares',
    isDark: false,
    pairId: 'everforest-dark',
    swatch: const Color(0xFFFDF6E3),
    accent: const Color(0xFF8DA101),
    definition: everforestLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF8DA101),
      secondary: const Color(0xFF3A94C5),
      tertiary: const Color(0xFFDFA000),
      background: const Color(0xFFF4F0D9),
      surface: const Color(0xFFFDF6E3),
      elevated: const Color(0xFFEDEADA),
      onSurface: const Color(0xFF5C6A72),
      onSurfaceVariant: const Color(0xFF939F91),
      outline: const Color(0xFFDDD8C0),
      appBarBg: const Color(0xFFEDEADA),
    ),
  ),

  // ── GitHub ────────────────────────────────────────────────────────────────
  EditorThemeMeta(
    id: 'github-dark',
    name: 'GitHub Dark',
    category: 'GitHub',
    isDark: true,
    pairId: 'github-light',
    swatch: const Color(0xFF0D1117),
    accent: const Color(0xFF79C0FF),
    definition: githubDarkDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF79C0FF),
      secondary: const Color(0xFFD2A8FF),
      tertiary: const Color(0xFF7EE787),
      background: const Color(0xFF0D1117),
      surface: const Color(0xFF161B22),
      elevated: const Color(0xFF21262D),
      onSurface: const Color(0xFFE6EDF3),
      onSurfaceVariant: const Color(0xFF8B949E),
      outline: const Color(0xFF30363D),
      outlineVariant: const Color(0xFF21262D),
      appBarBg: const Color(0xFF161B22),
    ),
  ),
  EditorThemeMeta(
    id: 'github-light',
    name: 'GitHub Light',
    category: 'GitHub',
    isDark: false,
    pairId: 'github-dark',
    swatch: const Color(0xFFFFFFFF),
    accent: const Color(0xFF0969DA),
    definition: githubLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF0969DA),
      secondary: const Color(0xFF8250DF),
      tertiary: const Color(0xFF1A7F37),
      background: const Color(0xFFF6F8FA),
      surface: Colors.white,
      elevated: const Color(0xFFF6F8FA),
      onSurface: const Color(0xFF24292F),
      onSurfaceVariant: const Color(0xFF57606A),
      outline: const Color(0xFFD0D7DE),
      outlineVariant: const Color(0xFFEAEEF2),
      appBarBg: const Color(0xFFEAEEF2),
    ),
  ),

  // ── Coloridos ─────────────────────────────────────────────────────────────
  EditorThemeMeta(
    id: 'synthwave-84',
    name: "SynthWave '84",
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF262335),
    accent: const Color(0xFFFF7EDB),
    definition: synthwave84Def,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFFF7EDB),
      secondary: const Color(0xFF36F9F6),
      tertiary: const Color(0xFFFEDE5D),
      background: const Color(0xFF262335),
      surface: const Color(0xFF2A2139),
      elevated: const Color(0xFF34294F),
      onSurface: const Color(0xFFF4EEE4),
      onSurfaceVariant: const Color(0xFF848BBD),
      outline: const Color(0xFF614D85),
      outlineVariant: const Color(0xFF34294F),
      appBarBg: const Color(0xFF241B2F),
    ),
  ),
  EditorThemeMeta(
    id: 'shades-of-purple',
    name: 'Shades of Purple',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF2D2B55),
    accent: const Color(0xFFFAD000),
    definition: shadesOfPurpleDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFFAD000),
      onPrimary: const Color(0xFF2D2B55),
      secondary: const Color(0xFFA599E9),
      tertiary: const Color(0xFFFF628C),
      background: const Color(0xFF2D2B55),
      surface: const Color(0xFF322F62),
      elevated: const Color(0xFF3D3A72),
      onSurface: const Color(0xFFFFFFFF),
      onSurfaceVariant: const Color(0xFFA599E9),
      outline: const Color(0xFF4D4A85),
      outlineVariant: const Color(0xFF3D3A72),
      appBarBg: const Color(0xFF1F1F41),
    ),
  ),
  EditorThemeMeta(
    id: 'andromeda',
    name: 'Andromeda',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF23262E),
    accent: const Color(0xFF00E8C6),
    definition: andromedaDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF00E8C6),
      secondary: const Color(0xFFC74DED),
      tertiary: const Color(0xFFFFE66D),
      background: const Color(0xFF23262E),
      surface: const Color(0xFF2B2F38),
      elevated: const Color(0xFF333743),
      onSurface: const Color(0xFFD5CED9),
      onSurfaceVariant: const Color(0xFF897F9C),
      outline: const Color(0xFF3A3F4B),
      outlineVariant: const Color(0xFF2B2F38),
      appBarBg: const Color(0xFF1B1D23),
    ),
  ),
  EditorThemeMeta(
    id: 'laserwave',
    name: 'Laserwave',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF27212E),
    accent: const Color(0xFFEB64B9),
    definition: laserwaveDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFEB64B9),
      secondary: const Color(0xFF74DFC4),
      tertiary: const Color(0xFFFFE261),
      background: const Color(0xFF27212E),
      surface: const Color(0xFF3A3242),
      elevated: const Color(0xFF4D4256),
      onSurface: const Color(0xFFE0DFE1),
      onSurfaceVariant: const Color(0xFF91889B),
      outline: const Color(0xFF5A4E63),
      outlineVariant: const Color(0xFF3A3242),
      appBarBg: const Color(0xFF1E1922),
    ),
  ),
  EditorThemeMeta(
    id: 'panda',
    name: 'Panda',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF292A2B),
    accent: const Color(0xFF19F9D8),
    definition: pandaDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF19F9D8),
      secondary: const Color(0xFFFF75B5),
      tertiary: const Color(0xFFFFB86C),
      background: const Color(0xFF292A2B),
      surface: const Color(0xFF333437),
      elevated: const Color(0xFF3D3E40),
      onSurface: const Color(0xFFE6E6E6),
      onSurfaceVariant: const Color(0xFF9A9B9F),
      outline: const Color(0xFF4A4B4D),
      outlineVariant: const Color(0xFF333437),
      appBarBg: const Color(0xFF1D1E20),
    ),
  ),
  EditorThemeMeta(
    id: 'cyberpunk-neon',
    name: 'Cyberpunk Neon',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF000B1E),
    accent: const Color(0xFF0ABDC6),
    definition: cyberpunkNeonDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF0ABDC6),
      onPrimary: const Color(0xFF000B1E),
      secondary: const Color(0xFFEA00D9),
      tertiary: const Color(0xFF00FF9C),
      background: const Color(0xFF000B1E),
      surface: const Color(0xFF021834),
      elevated: const Color(0xFF033D4B),
      onSurface: const Color(0xFFD7D7D7),
      onSurfaceVariant: const Color(0xFF3B7DA8),
      outline: const Color(0xFF123E7C),
      outlineVariant: const Color(0xFF021834),
      appBarBg: const Color(0xFF000714),
    ),
  ),
  EditorThemeMeta(
    id: 'material-palenight',
    name: 'Material Palenight',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF292D3E),
    accent: const Color(0xFF82AAFF),
    definition: materialPalenightDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFF82AAFF),
      secondary: const Color(0xFFC792EA),
      tertiary: const Color(0xFFC3E88D),
      background: const Color(0xFF292D3E),
      surface: const Color(0xFF32374D),
      elevated: const Color(0xFF3C435E),
      onSurface: const Color(0xFFA6ACCD),
      onSurfaceVariant: const Color(0xFF676E95),
      outline: const Color(0xFF4A5173),
      outlineVariant: const Color(0xFF32374D),
      appBarBg: const Color(0xFF1F2233),
    ),
  ),
  EditorThemeMeta(
    id: 'horizon',
    name: 'Horizon',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF1C1E26),
    accent: const Color(0xFFE95678),
    definition: horizonDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFE95678),
      secondary: const Color(0xFFFAB795),
      tertiary: const Color(0xFF25B2BC),
      background: const Color(0xFF1C1E26),
      surface: const Color(0xFF232530),
      elevated: const Color(0xFF2E303E),
      onSurface: const Color(0xFFD5D8DA),
      onSurfaceVariant: const Color(0xFF6C6F93),
      outline: const Color(0xFF3D3F4E),
      outlineVariant: const Color(0xFF232530),
      appBarBg: const Color(0xFF16161C),
    ),
  ),
  EditorThemeMeta(
    id: 'cobalt2',
    name: 'Cobalt2',
    category: 'Coloridos',
    isDark: true,
    swatch: const Color(0xFF193549),
    accent: const Color(0xFFFFC600),
    definition: cobalt2Def,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFFFC600),
      onPrimary: const Color(0xFF193549),
      secondary: const Color(0xFF9EFFFF),
      tertiary: const Color(0xFFFF628C),
      background: const Color(0xFF193549),
      surface: const Color(0xFF1F4662),
      elevated: const Color(0xFF15232D),
      onSurface: const Color(0xFFFFFFFF),
      onSurfaceVariant: const Color(0xFF88B5CE),
      outline: const Color(0xFF0D3A58),
      outlineVariant: const Color(0xFF1F4662),
      appBarBg: const Color(0xFF122738),
    ),
  ),
  EditorThemeMeta(
    id: 'ayu-mirage',
    name: 'Ayu Mirage',
    category: 'Coloridos',
    isDark: true,
    pairId: 'ayu-light',
    swatch: const Color(0xFF1F2430),
    accent: const Color(0xFFFFCC66),
    definition: ayuMirageDef,
    palette: AppPalette.from(
      isDark: true,
      primary: const Color(0xFFFFCC66),
      onPrimary: const Color(0xFF1F2430),
      secondary: const Color(0xFF73D0FF),
      tertiary: const Color(0xFFBAE67E),
      background: const Color(0xFF1F2430),
      surface: const Color(0xFF242936),
      elevated: const Color(0xFF2C3242),
      onSurface: const Color(0xFFCBCCC6),
      onSurfaceVariant: const Color(0xFF707A8C),
      outline: const Color(0xFF34455A),
      outlineVariant: const Color(0xFF242936),
      appBarBg: const Color(0xFF171B24),
    ),
  ),
  EditorThemeMeta(
    id: 'ayu-light',
    name: 'Ayu Light',
    category: 'Coloridos',
    isDark: false,
    pairId: 'ayu-mirage',
    swatch: const Color(0xFFFAFAFA),
    accent: const Color(0xFFFF9940),
    definition: ayuLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFFFF9940),
      onPrimary: Colors.white,
      secondary: const Color(0xFF399EE6),
      tertiary: const Color(0xFF86B300),
      background: const Color(0xFFF3F4F5),
      surface: const Color(0xFFFAFAFA),
      elevated: const Color(0xFFE7E8E9),
      onSurface: const Color(0xFF5C6773),
      onSurfaceVariant: const Color(0xFF8A9199),
      outline: const Color(0xFFD9DCDF),
      appBarBg: const Color(0xFFFF9940),
    ),
  ),
  EditorThemeMeta(
    id: 'bluloco-light',
    name: 'Bluloco Light',
    category: 'Coloridos',
    isDark: false,
    swatch: const Color(0xFFF9F9F9),
    accent: const Color(0xFF0098DD),
    definition: blulocoLightDef,
    palette: AppPalette.from(
      isDark: false,
      primary: const Color(0xFF0098DD),
      secondary: const Color(0xFF7A82DA),
      tertiary: const Color(0xFF23974A),
      background: const Color(0xFFEFEFEF),
      surface: const Color(0xFFF9F9F9),
      elevated: const Color(0xFFE4E4E4),
      onSurface: const Color(0xFF383A42),
      onSurfaceVariant: const Color(0xFF8E8F93),
      outline: const Color(0xFFD3D3D5),
      appBarBg: const Color(0xFF0069A8),
      onAppBar: Colors.white,
    ),
  ),
];

/// Índice por id para lookup O(1).
final kEditorThemeById = {for (final t in kEditorThemes) t.id: t};

/// Temas agrupados por categoría, respetando el orden del catálogo.
Map<String, List<EditorThemeMeta>> groupedEditorThemes({bool? onlyDark}) {
  final grouped = <String, List<EditorThemeMeta>>{};
  for (final t in kEditorThemes) {
    if (onlyDark != null && t.isDark != onlyDark) continue;
    grouped.putIfAbsent(t.category, () => []).add(t);
  }
  return grouped;
}

// ── Unified theme store ──────────────────────────────────────────────────────

/// Drives the Monaco theme for ALL editors in the app and keeps
/// the Flutter app brightness (dark/light) in sync automatically.
class EditorThemeStore extends ChangeNotifier {
  static const _prefKey = 'editor_theme_id';
  static const defaultThemeId = 'oracle-dark';

  String _themeId = defaultThemeId;
  String get themeId => _themeId;
  MonacoTheme get monacoTheme => MonacoTheme(_themeId);

  EditorThemeMeta get currentMeta =>
      kEditorThemeById[_themeId] ?? kEditorThemes.first;

  /// Id del tema equivalente en la luminosidad opuesta.
  String get pairedThemeId =>
      currentMeta.pairId ??
      (currentMeta.isDark ? 'oracle-light' : defaultThemeId);

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && kEditorThemeById.containsKey(saved)) {
      _themeId = saved;
    }
    await _syncFlutterTheme();
    notifyListeners();
  }

  Future<void> setTheme(String id) async {
    if (_themeId == id || !kEditorThemeById.containsKey(id)) return;
    _themeId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, id);
    await _syncFlutterTheme();
  }

  Future<void> _syncFlutterTheme() async {
    final isDark = currentMeta.isDark;
    await themeStore.setMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  /// Registers all custom theme definitions in a MonacoController.
  /// Must be called in onReady before setTheme with a custom id.
  static Future<void> defineAllThemes(MonacoController ctrl) => Future.wait([
    for (final t in kEditorThemes)
      if (t.definition != null) ctrl.defineTheme(t.definition!),
  ]);
}

final editorThemeStore = EditorThemeStore();

// ── Muestra de color para los pickers ───────────────────────────────────────

/// Cuadrito bicolor: fondo del tema + triángulo con su color de acento.
class ThemeSwatch extends StatelessWidget {
  final Color bg;
  final Color accent;
  final double size;

  const ThemeSwatch({
    super.key,
    required this.bg,
    required this.accent,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 0.6,
        ),
      ),
      child: Align(
        alignment: Alignment.bottomRight,
        child: Container(
          width: size * 0.55,
          height: size * 0.55,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(size * 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
