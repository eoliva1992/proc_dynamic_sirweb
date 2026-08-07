import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '_editor_oracle_theme.dart';

// ── Theme handles ──────────────────────────────────────────────────────────

const monokaiTheme = MonacoTheme('monokai');
const draculaTheme = MonacoTheme('dracula');
const solarizedDarkTheme = MonacoTheme('solarized-dark');
const solarizedLightTheme = MonacoTheme('solarized-light');
const oneDarkTheme = MonacoTheme('one-dark');

// ── Theme metadata for the picker ─────────────────────────────────────────

typedef EditorThemeMeta = ({
  String id,
  String name,
  Color swatch,
  String category,
  bool isDark,
});

const kEditorThemes = <EditorThemeMeta>[
  (
    id: 'oracle-dark',
    name: 'Oracle Dark',
    swatch: Color(0xFF1A1A2E),
    category: 'Oracle',
    isDark: true,
  ),
  (
    id: 'oracle-light',
    name: 'Oracle Light',
    swatch: Color(0xFFFAFAFA),
    category: 'Oracle',
    isDark: false,
  ),
  (
    id: 'vs-dark',
    name: 'VS Dark',
    swatch: Color(0xFF1E1E1E),
    category: 'VS Code',
    isDark: true,
  ),
  (
    id: 'vs',
    name: 'VS Light',
    swatch: Color(0xFFFFFFFF),
    category: 'VS Code',
    isDark: false,
  ),
  (
    id: 'hc-black',
    name: 'High Contrast Dark',
    swatch: Color(0xFF000000),
    category: 'VS Code',
    isDark: true,
  ),
  (
    id: 'hc-light',
    name: 'High Contrast Light',
    swatch: Color(0xFFFFFFFF),
    category: 'VS Code',
    isDark: false,
  ),
  (
    id: 'monokai',
    name: 'Monokai',
    swatch: Color(0xFF272822),
    category: 'Populares',
    isDark: true,
  ),
  (
    id: 'dracula',
    name: 'Dracula',
    swatch: Color(0xFF282A36),
    category: 'Populares',
    isDark: true,
  ),
  (
    id: 'solarized-dark',
    name: 'Solarized Dark',
    swatch: Color(0xFF002B36),
    category: 'Populares',
    isDark: true,
  ),
  (
    id: 'solarized-light',
    name: 'Solarized Light',
    swatch: Color(0xFFFDF6E3),
    category: 'Populares',
    isDark: false,
  ),
  (
    id: 'one-dark',
    name: 'One Dark',
    swatch: Color(0xFF282C34),
    category: 'Populares',
    isDark: true,
  ),
];

// ── Unified theme store ──────────────────────────────────────────────────────

/// Drives the Monaco theme for ALL editors in the app and keeps
/// the Flutter app brightness (dark/light) in sync automatically.
class EditorThemeStore extends ChangeNotifier {
  static const _prefKey = 'editor_theme_id';

  String _themeId = 'oracle-dark';
  String get themeId => _themeId;
  MonacoTheme get monacoTheme => MonacoTheme(_themeId);

  EditorThemeMeta get currentMeta => kEditorThemes.firstWhere(
    (t) => t.id == _themeId,
    orElse: () => kEditorThemes.first,
  );

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && kEditorThemes.any((t) => t.id == saved)) {
      _themeId = saved;
    }
    await _syncFlutterTheme();
    notifyListeners();
  }

  Future<void> setTheme(String id) async {
    if (_themeId == id) return;
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
  static Future<void> defineAllThemes(MonacoController ctrl) async {
    await ctrl.defineTheme(oracleDark);
    await ctrl.defineTheme(oracleLight);
    await ctrl.defineTheme(monokaiDef);
    await ctrl.defineTheme(draculaDef);
    await ctrl.defineTheme(solarizedDarkDef);
    await ctrl.defineTheme(solarizedLightDef);
    await ctrl.defineTheme(oneDarkDef);
  }
}

final editorThemeStore = EditorThemeStore();

// ── Theme definitions ──────────────────────────────────────────────────────

const monokaiDef = MonacoThemeDefinition(
  id: 'monokai',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'F92672', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '75715E',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'E6DB74'),
    MonacoThemeRule(token: 'number', foreground: 'AE81FF'),
    MonacoThemeRule(token: 'identifier', foreground: 'A6E22E'),
    MonacoThemeRule(token: 'operator', foreground: 'F8F8F2'),
    MonacoThemeRule(token: 'delimiter', foreground: 'F8F8F2'),
  ],
  colors: {
    'editor.background': '#272822',
    'editor.foreground': '#F8F8F2',
    'editorLineNumber.foreground': '#90908A',
    'editorLineNumber.activeForeground': '#CFCFC2',
    'editor.lineHighlightBackground': '#3E3D32',
    'editor.selectionBackground': '#49483E',
    'editorCursor.foreground': '#F8F8F0',
    'editor.inactiveSelectionBackground': '#3E3D3280',
    'editorBracketMatch.background': '#FE57A133',
    'editorBracketMatch.border': '#FE57A1',
    'editorIndentGuide.background1': '#3B3A32',
  },
);

const draculaDef = MonacoThemeDefinition(
  id: 'dracula',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'FF79C6', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '6272A4',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'F1FA8C'),
    MonacoThemeRule(token: 'number', foreground: 'BD93F9'),
    MonacoThemeRule(token: 'identifier', foreground: '8BE9FD'),
    MonacoThemeRule(token: 'operator', foreground: 'FF79C6'),
    MonacoThemeRule(token: 'delimiter', foreground: 'F8F8F2'),
  ],
  colors: {
    'editor.background': '#282A36',
    'editor.foreground': '#F8F8F2',
    'editorLineNumber.foreground': '#6272A4',
    'editorLineNumber.activeForeground': '#F8F8F2',
    'editor.lineHighlightBackground': '#44475A',
    'editor.selectionBackground': '#44475A',
    'editorCursor.foreground': '#F8F8F2',
    'editor.inactiveSelectionBackground': '#44475A80',
    'editorBracketMatch.background': '#BD93F933',
    'editorBracketMatch.border': '#BD93F9',
    'editorIndentGuide.background1': '#44475A',
  },
);

const solarizedDarkDef = MonacoThemeDefinition(
  id: 'solarized-dark',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: '859900', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '586E75',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: '2AA198'),
    MonacoThemeRule(token: 'number', foreground: 'D33682'),
    MonacoThemeRule(token: 'identifier', foreground: '268BD2'),
    MonacoThemeRule(token: 'operator', foreground: '859900'),
    MonacoThemeRule(token: 'delimiter', foreground: '657B83'),
  ],
  colors: {
    'editor.background': '#002B36',
    'editor.foreground': '#839496',
    'editorLineNumber.foreground': '#586E75',
    'editorLineNumber.activeForeground': '#839496',
    'editor.lineHighlightBackground': '#073642',
    'editor.selectionBackground': '#073642',
    'editorCursor.foreground': '#839496',
    'editorBracketMatch.background': '#268BD233',
    'editorBracketMatch.border': '#268BD2',
    'editorIndentGuide.background1': '#073642',
  },
);

const solarizedLightDef = MonacoThemeDefinition(
  id: 'solarized-light',
  base: MonacoBaseTheme.vs,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: '859900', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '93A1A1',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: '2AA198'),
    MonacoThemeRule(token: 'number', foreground: 'D33682'),
    MonacoThemeRule(token: 'identifier', foreground: '268BD2'),
    MonacoThemeRule(token: 'operator', foreground: '859900'),
    MonacoThemeRule(token: 'delimiter', foreground: '657B83'),
  ],
  colors: {
    'editor.background': '#FDF6E3',
    'editor.foreground': '#657B83',
    'editorLineNumber.foreground': '#93A1A1',
    'editorLineNumber.activeForeground': '#657B83',
    'editor.lineHighlightBackground': '#EEE8D5',
    'editor.selectionBackground': '#EEE8D5',
    'editorCursor.foreground': '#657B83',
    'editorBracketMatch.background': '#268BD233',
    'editorBracketMatch.border': '#268BD2',
    'editorIndentGuide.background1': '#EEE8D5',
  },
);

const oneDarkDef = MonacoThemeDefinition(
  id: 'one-dark',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'C678DD', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '5C6370',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: '98C379'),
    MonacoThemeRule(token: 'number', foreground: 'D19A66'),
    MonacoThemeRule(token: 'identifier', foreground: '61AFEF'),
    MonacoThemeRule(token: 'operator', foreground: '56B6C2'),
    MonacoThemeRule(token: 'delimiter', foreground: 'ABB2BF'),
  ],
  colors: {
    'editor.background': '#282C34',
    'editor.foreground': '#ABB2BF',
    'editorLineNumber.foreground': '#4B5263',
    'editorLineNumber.activeForeground': '#ABB2BF',
    'editor.lineHighlightBackground': '#2C313A',
    'editor.selectionBackground': '#3E4451',
    'editorCursor.foreground': '#528BFF',
    'editor.inactiveSelectionBackground': '#3E445180',
    'editorBracketMatch.background': '#528BFF33',
    'editorBracketMatch.border': '#528BFF',
    'editorIndentGuide.background1': '#3B4048',
  },
);
