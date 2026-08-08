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
  (
    id: 'github-dark',
    name: 'GitHub Dark',
    swatch: Color(0xFF0D1117),
    category: 'GitHub',
    isDark: true,
  ),
  (
    id: 'github-light',
    name: 'GitHub Light',
    swatch: Color(0xFFFFFFFF),
    category: 'GitHub',
    isDark: false,
  ),
  (
    id: 'nord',
    name: 'Nord',
    swatch: Color(0xFF2E3440),
    category: 'Populares',
    isDark: true,
  ),
  (
    id: 'tokyo-night',
    name: 'Tokyo Night',
    swatch: Color(0xFF1A1B26),
    category: 'Populares',
    isDark: true,
  ),
  (
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    swatch: Color(0xFF1E1E2E),
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
    await ctrl.defineTheme(githubDarkDef);
    await ctrl.defineTheme(githubLightDef);
    await ctrl.defineTheme(nordDef);
    await ctrl.defineTheme(tokyoNightDef);
    await ctrl.defineTheme(catppuccinMochaDef);
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

const githubDarkDef = MonacoThemeDefinition(
  id: 'github-dark',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'FF7B72', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '8B949E',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'A5D6FF'),
    MonacoThemeRule(token: 'number', foreground: '79C0FF'),
    MonacoThemeRule(token: 'identifier', foreground: 'D2A8FF'),
    MonacoThemeRule(token: 'operator', foreground: 'FF7B72'),
    MonacoThemeRule(token: 'delimiter', foreground: 'C9D1D9'),
  ],
  colors: {
    'editor.background': '#0D1117',
    'editor.foreground': '#C9D1D9',
    'editorLineNumber.foreground': '#6E7681',
    'editorLineNumber.activeForeground': '#C9D1D9',
    'editor.lineHighlightBackground': '#161B22',
    'editor.selectionBackground': '#388BFD3D',
    'editorCursor.foreground': '#C9D1D9',
    'editor.inactiveSelectionBackground': '#388BFD26',
    'editorBracketMatch.background': '#388BFD33',
    'editorBracketMatch.border': '#388BFD',
    'editorIndentGuide.background1': '#21262D',
  },
);

const githubLightDef = MonacoThemeDefinition(
  id: 'github-light',
  base: MonacoBaseTheme.vs,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'CF222E', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '6E7781',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: '0A3069'),
    MonacoThemeRule(token: 'number', foreground: '0550AE'),
    MonacoThemeRule(token: 'identifier', foreground: '8250DF'),
    MonacoThemeRule(token: 'operator', foreground: 'CF222E'),
    MonacoThemeRule(token: 'delimiter', foreground: '24292F'),
  ],
  colors: {
    'editor.background': '#FFFFFF',
    'editor.foreground': '#24292F',
    'editorLineNumber.foreground': '#57606A',
    'editorLineNumber.activeForeground': '#24292F',
    'editor.lineHighlightBackground': '#F6F8FA',
    'editor.selectionBackground': '#0969DA3D',
    'editorCursor.foreground': '#24292F',
    'editorBracketMatch.background': '#0969DA33',
    'editorBracketMatch.border': '#0969DA',
    'editorIndentGuide.background1': '#D0D7DE',
  },
);

const nordDef = MonacoThemeDefinition(
  id: 'nord',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: '81A1C1', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '616E88',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'A3BE8C'),
    MonacoThemeRule(token: 'number', foreground: 'B48EAD'),
    MonacoThemeRule(token: 'identifier', foreground: '88C0D0'),
    MonacoThemeRule(token: 'operator', foreground: '81A1C1'),
    MonacoThemeRule(token: 'delimiter', foreground: 'D8DEE9'),
  ],
  colors: {
    'editor.background': '#2E3440',
    'editor.foreground': '#D8DEE9',
    'editorLineNumber.foreground': '#616E88',
    'editorLineNumber.activeForeground': '#D8DEE9',
    'editor.lineHighlightBackground': '#3B4252',
    'editor.selectionBackground': '#434C5E',
    'editorCursor.foreground': '#D8DEE9',
    'editor.inactiveSelectionBackground': '#434C5E80',
    'editorBracketMatch.background': '#88C0D033',
    'editorBracketMatch.border': '#88C0D0',
    'editorIndentGuide.background1': '#434C5E',
  },
);

const tokyoNightDef = MonacoThemeDefinition(
  id: 'tokyo-night',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'BB9AF7', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '565F89',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: '9ECE6A'),
    MonacoThemeRule(token: 'number', foreground: 'FF9E64'),
    MonacoThemeRule(token: 'identifier', foreground: '7AA2F7'),
    MonacoThemeRule(token: 'operator', foreground: '89DDFF'),
    MonacoThemeRule(token: 'delimiter', foreground: 'A9B1D6'),
  ],
  colors: {
    'editor.background': '#1A1B26',
    'editor.foreground': '#A9B1D6',
    'editorLineNumber.foreground': '#565F89',
    'editorLineNumber.activeForeground': '#C0CAF5',
    'editor.lineHighlightBackground': '#1F2335',
    'editor.selectionBackground': '#364A7080',
    'editorCursor.foreground': '#C0CAF5',
    'editor.inactiveSelectionBackground': '#364A7040',
    'editorBracketMatch.background': '#7AA2F733',
    'editorBracketMatch.border': '#7AA2F7',
    'editorIndentGuide.background1': '#3B4261',
  },
);

const catppuccinMochaDef = MonacoThemeDefinition(
  id: 'catppuccin-mocha',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'CBA6F7', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '6C7086',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'A6E3A1'),
    MonacoThemeRule(token: 'number', foreground: 'FAB387'),
    MonacoThemeRule(token: 'identifier', foreground: '89B4FA'),
    MonacoThemeRule(token: 'operator', foreground: '89DCEB'),
    MonacoThemeRule(token: 'delimiter', foreground: 'CDD6F4'),
  ],
  colors: {
    'editor.background': '#1E1E2E',
    'editor.foreground': '#CDD6F4',
    'editorLineNumber.foreground': '#6C7086',
    'editorLineNumber.activeForeground': '#CDD6F4',
    'editor.lineHighlightBackground': '#2A2B3C',
    'editor.selectionBackground': '#89B4FA40',
    'editorCursor.foreground': '#F5E0DC',
    'editor.inactiveSelectionBackground': '#89B4FA26',
    'editorBracketMatch.background': '#CBA6F733',
    'editorBracketMatch.border': '#CBA6F7',
    'editorIndentGuide.background1': '#313244',
  },
);
