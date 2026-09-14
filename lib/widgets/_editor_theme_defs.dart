import 'package:flutter_monaco/flutter_monaco.dart';

// ── Fábrica compacta de temas Monaco ────────────────────────────────────────
//
// Cada tema se describe con un puñado de colores (hex SIN '#'); el resto de
// claves de Monaco se derivan con valores por defecto sensatos.

MonacoThemeDefinition _def({
  required String id,
  required bool dark,
  required String bg,
  required String fg,
  required String keyword,
  required String comment,
  required String string,
  required String number,
  required String identifier,
  required String lineHighlight,
  String? selection,
  String? operator,
  String? delimiter,
  String? cursor,
  String? lineNumber,
  String? indentGuide,
  String? bracket,
}) {
  final sel = selection ?? lineHighlight;
  final brk = bracket ?? identifier;
  return MonacoThemeDefinition(
    id: id,
    base: dark ? MonacoBaseTheme.vsDark : MonacoBaseTheme.vs,
    rules: [
      MonacoThemeRule(token: 'keyword', foreground: keyword, fontStyle: 'bold'),
      MonacoThemeRule(
        token: 'comment',
        foreground: comment,
        fontStyle: 'italic',
      ),
      MonacoThemeRule(token: 'string', foreground: string),
      MonacoThemeRule(token: 'number', foreground: number),
      MonacoThemeRule(token: 'identifier', foreground: identifier),
      MonacoThemeRule(token: 'operator', foreground: operator ?? keyword),
      MonacoThemeRule(token: 'delimiter', foreground: delimiter ?? fg),
    ],
    colors: {
      'editor.background': '#$bg',
      'editor.foreground': '#$fg',
      'editorLineNumber.foreground': '#${lineNumber ?? comment}',
      'editorLineNumber.activeForeground': '#$fg',
      'editor.lineHighlightBackground': '#$lineHighlight',
      'editor.selectionBackground': '#$sel',
      'editor.inactiveSelectionBackground': '#${sel}80',
      'editorCursor.foreground': '#${cursor ?? fg}',
      'editorIndentGuide.background1': '#${indentGuide ?? lineHighlight}',
      'editorBracketMatch.background': '#${brk}33',
      'editorBracketMatch.border': '#$brk',
    },
  );
}

// ── Clásicos ────────────────────────────────────────────────────────────────

final monokaiDef = _def(
  id: 'monokai',
  dark: true,
  bg: '272822',
  fg: 'F8F8F2',
  keyword: 'F92672',
  comment: '75715E',
  string: 'E6DB74',
  number: 'AE81FF',
  identifier: 'A6E22E',
  lineHighlight: '3E3D32',
  selection: '49483E',
  operator: 'F8F8F2',
  lineNumber: '90908A',
  indentGuide: '3B3A32',
  bracket: 'FE57A1',
);

final draculaDef = _def(
  id: 'dracula',
  dark: true,
  bg: '282A36',
  fg: 'F8F8F2',
  keyword: 'FF79C6',
  comment: '6272A4',
  string: 'F1FA8C',
  number: 'BD93F9',
  identifier: '8BE9FD',
  lineHighlight: '44475A',
  bracket: 'BD93F9',
);

final solarizedDarkDef = _def(
  id: 'solarized-dark',
  dark: true,
  bg: '002B36',
  fg: '839496',
  keyword: '859900',
  comment: '586E75',
  string: '2AA198',
  number: 'D33682',
  identifier: '268BD2',
  lineHighlight: '073642',
  delimiter: '657B83',
);

final solarizedLightDef = _def(
  id: 'solarized-light',
  dark: false,
  bg: 'FDF6E3',
  fg: '657B83',
  keyword: '859900',
  comment: '93A1A1',
  string: '2AA198',
  number: 'D33682',
  identifier: '268BD2',
  lineHighlight: 'EEE8D5',
  delimiter: '657B83',
);

final oneDarkDef = _def(
  id: 'one-dark',
  dark: true,
  bg: '282C34',
  fg: 'ABB2BF',
  keyword: 'C678DD',
  comment: '5C6370',
  string: '98C379',
  number: 'D19A66',
  identifier: '61AFEF',
  lineHighlight: '2C313A',
  selection: '3E4451',
  operator: '56B6C2',
  cursor: '528BFF',
  lineNumber: '4B5263',
  indentGuide: '3B4048',
  bracket: '528BFF',
);

final oneLightDef = _def(
  id: 'one-light',
  dark: false,
  bg: 'FAFAFA',
  fg: '383A42',
  keyword: 'A626A4',
  comment: 'A0A1A7',
  string: '50A14F',
  number: '986801',
  identifier: '4078F2',
  lineHighlight: 'F0F0F1',
  selection: 'E5E5E6',
  operator: '0184BC',
  bracket: '4078F2',
);

final githubDarkDef = _def(
  id: 'github-dark',
  dark: true,
  bg: '0D1117',
  fg: 'C9D1D9',
  keyword: 'FF7B72',
  comment: '8B949E',
  string: 'A5D6FF',
  number: '79C0FF',
  identifier: 'D2A8FF',
  lineHighlight: '161B22',
  selection: '388BFD3D',
  delimiter: 'C9D1D9',
  lineNumber: '6E7681',
  indentGuide: '21262D',
  bracket: '388BFD',
);

final githubLightDef = _def(
  id: 'github-light',
  dark: false,
  bg: 'FFFFFF',
  fg: '24292F',
  keyword: 'CF222E',
  comment: '6E7781',
  string: '0A3069',
  number: '0550AE',
  identifier: '8250DF',
  lineHighlight: 'F6F8FA',
  selection: '0969DA3D',
  lineNumber: '57606A',
  indentGuide: 'D0D7DE',
  bracket: '0969DA',
);

final nordDef = _def(
  id: 'nord',
  dark: true,
  bg: '2E3440',
  fg: 'D8DEE9',
  keyword: '81A1C1',
  comment: '616E88',
  string: 'A3BE8C',
  number: 'B48EAD',
  identifier: '88C0D0',
  lineHighlight: '3B4252',
  selection: '434C5E',
  indentGuide: '434C5E',
);

final tokyoNightDef = _def(
  id: 'tokyo-night',
  dark: true,
  bg: '1A1B26',
  fg: 'A9B1D6',
  keyword: 'BB9AF7',
  comment: '565F89',
  string: '9ECE6A',
  number: 'FF9E64',
  identifier: '7AA2F7',
  lineHighlight: '1F2335',
  selection: '364A7080',
  operator: '89DDFF',
  cursor: 'C0CAF5',
  indentGuide: '3B4261',
  bracket: '7AA2F7',
);

final catppuccinMochaDef = _def(
  id: 'catppuccin-mocha',
  dark: true,
  bg: '1E1E2E',
  fg: 'CDD6F4',
  keyword: 'CBA6F7',
  comment: '6C7086',
  string: 'A6E3A1',
  number: 'FAB387',
  identifier: '89B4FA',
  lineHighlight: '2A2B3C',
  selection: '89B4FA40',
  operator: '89DCEB',
  cursor: 'F5E0DC',
  indentGuide: '313244',
  bracket: 'CBA6F7',
);

final catppuccinLatteDef = _def(
  id: 'catppuccin-latte',
  dark: false,
  bg: 'EFF1F5',
  fg: '4C4F69',
  keyword: '8839EF',
  comment: '9CA0B0',
  string: '40A02B',
  number: 'FE640B',
  identifier: '1E66F5',
  lineHighlight: 'E6E9EF',
  selection: '1E66F540',
  operator: '179299',
  bracket: '8839EF',
);

final gruvboxDarkDef = _def(
  id: 'gruvbox-dark',
  dark: true,
  bg: '282828',
  fg: 'EBDBB2',
  keyword: 'FB4934',
  comment: '928374',
  string: 'B8BB26',
  number: 'D3869B',
  identifier: '83A598',
  lineHighlight: '3C3836',
  selection: '504945',
  operator: 'FE8019',
  bracket: 'FABD2F',
);

final gruvboxLightDef = _def(
  id: 'gruvbox-light',
  dark: false,
  bg: 'FBF1C7',
  fg: '3C3836',
  keyword: '9D0006',
  comment: '928374',
  string: '79740E',
  number: '8F3F71',
  identifier: '076678',
  lineHighlight: 'EBDBB2',
  selection: 'D5C4A1',
  operator: 'AF3A03',
  bracket: 'B57614',
);

final rosePineMoonDef = _def(
  id: 'rose-pine-moon',
  dark: true,
  bg: '232136',
  fg: 'E0DEF4',
  keyword: '3E8FB0',
  comment: '6E6A86',
  string: 'F6C177',
  number: 'EA9A97',
  identifier: '9CCFD8',
  lineHighlight: '2A273F',
  selection: '44415A',
  operator: 'C4A7E7',
  bracket: 'C4A7E7',
);

final rosePineDawnDef = _def(
  id: 'rose-pine-dawn',
  dark: false,
  bg: 'FAF4ED',
  fg: '575279',
  keyword: '286983',
  comment: '9893A5',
  string: 'EA9D34',
  number: 'D7827E',
  identifier: '56949F',
  lineHighlight: 'FFFAF3',
  selection: 'F2E9E1',
  operator: '907AA9',
  bracket: '907AA9',
);

final nightOwlDef = _def(
  id: 'night-owl',
  dark: true,
  bg: '011627',
  fg: 'D6DEEB',
  keyword: 'C792EA',
  comment: '637777',
  string: 'ECC48D',
  number: 'F78C6C',
  identifier: '82AAFF',
  lineHighlight: '0B2942',
  selection: '1D3B53',
  operator: '7FDBCA',
  cursor: '80A4C2',
  bracket: '7FDBCA',
);

final lightOwlDef = _def(
  id: 'light-owl',
  dark: false,
  bg: 'FBFBFB',
  fg: '403F53',
  keyword: '994CC3',
  comment: '989FB1',
  string: 'C96765',
  number: 'AA0982',
  identifier: '4876D6',
  lineHighlight: 'F0F0F0',
  selection: 'E0E0E0',
  operator: '0C969B',
  bracket: '0C969B',
);

final kanagawaDef = _def(
  id: 'kanagawa',
  dark: true,
  bg: '1F1F28',
  fg: 'DCD7BA',
  keyword: '957FB8',
  comment: '727169',
  string: '98BB6C',
  number: 'D27E99',
  identifier: '7E9CD8',
  lineHighlight: '2A2A37',
  selection: '363646',
  operator: 'C0A36E',
  bracket: '7FB4CA',
);

final everforestDarkDef = _def(
  id: 'everforest-dark',
  dark: true,
  bg: '2D353B',
  fg: 'D3C6AA',
  keyword: 'E67E80',
  comment: '859289',
  string: 'A7C080',
  number: 'D699B6',
  identifier: '7FBBB3',
  lineHighlight: '343F44',
  selection: '475258',
  operator: 'E69875',
  bracket: 'DBBC7F',
);

final everforestLightDef = _def(
  id: 'everforest-light',
  dark: false,
  bg: 'FDF6E3',
  fg: '5C6A72',
  keyword: 'F85552',
  comment: '939F91',
  string: '8DA101',
  number: 'DF69BA',
  identifier: '3A94C5',
  lineHighlight: 'F4F0D9',
  selection: 'EDEADA',
  operator: 'F57D26',
  bracket: 'DFA000',
);

// ── Coloridos ───────────────────────────────────────────────────────────────

final synthwave84Def = _def(
  id: 'synthwave-84',
  dark: true,
  bg: '262335',
  fg: 'F92AAD',
  keyword: 'FEDE5D',
  comment: '848BBD',
  string: 'FF8B39',
  number: 'F97E72',
  identifier: '36F9F6',
  lineHighlight: '34294F',
  selection: '463465',
  operator: 'FEDE5D',
  delimiter: 'E0E0E0',
  cursor: 'F92AAD',
  bracket: '36F9F6',
);

final shadesOfPurpleDef = _def(
  id: 'shades-of-purple',
  dark: true,
  bg: '2D2B55',
  fg: 'FFFFFF',
  keyword: 'FF9D00',
  comment: 'B362FF',
  string: 'A5FF90',
  number: 'FF628C',
  identifier: '9EFFFF',
  lineHighlight: '1F1F41',
  selection: '3D3A72',
  operator: 'FF9D00',
  cursor: 'FAD000',
  bracket: 'FAD000',
);

final andromedaDef = _def(
  id: 'andromeda',
  dark: true,
  bg: '23262E',
  fg: 'D5CED9',
  keyword: 'C74DED',
  comment: '746F77',
  string: '96E072',
  number: 'F39C12',
  identifier: '00E8C6',
  lineHighlight: '2B2F38',
  selection: '3A3F4B',
  operator: 'EE5D43',
  bracket: '00E8C6',
);

final laserwaveDef = _def(
  id: 'laserwave',
  dark: true,
  bg: '27212E',
  fg: 'E0DFE1',
  keyword: 'EB64B9',
  comment: '91889B',
  string: 'B4DCE7',
  number: 'FFE261',
  identifier: '40B4C4',
  lineHighlight: '3A3242',
  selection: '4D4256',
  operator: '74DFC4',
  cursor: 'FFE261',
  bracket: 'EB64B9',
);

final pandaDef = _def(
  id: 'panda',
  dark: true,
  bg: '292A2B',
  fg: 'E6E6E6',
  keyword: 'FF75B5',
  comment: '676B79',
  string: '19F9D8',
  number: 'FFB86C',
  identifier: '45A9F9',
  lineHighlight: '333437',
  selection: '3D3E40',
  operator: 'FF75B5',
  bracket: '19F9D8',
);

final cyberpunkNeonDef = _def(
  id: 'cyberpunk-neon',
  dark: true,
  bg: '000B1E',
  fg: '0ABDC6',
  keyword: 'FF0055',
  comment: '123E7C',
  string: 'D300C4',
  number: 'F57800',
  identifier: '00FF9C',
  lineHighlight: '00224466',
  selection: '033D4B',
  operator: 'EA00D9',
  delimiter: '0ABDC6',
  cursor: 'FF0055',
  bracket: 'EA00D9',
);

final materialPalenightDef = _def(
  id: 'material-palenight',
  dark: true,
  bg: '292D3E',
  fg: 'A6ACCD',
  keyword: 'C792EA',
  comment: '676E95',
  string: 'C3E88D',
  number: 'F78C6C',
  identifier: '82AAFF',
  lineHighlight: '32374D',
  selection: '3C435E',
  operator: '89DDFF',
  bracket: '82AAFF',
);

final horizonDef = _def(
  id: 'horizon',
  dark: true,
  bg: '1C1E26',
  fg: 'D5D8DA',
  keyword: 'B877DB',
  comment: '6C6F93',
  string: 'FAB795',
  number: 'F09383',
  identifier: '25B2BC',
  lineHighlight: '232530',
  selection: '2E303E',
  operator: 'E95678',
  bracket: 'E95678',
);

final cobalt2Def = _def(
  id: 'cobalt2',
  dark: true,
  bg: '193549',
  fg: 'FFFFFF',
  keyword: 'FF9D00',
  comment: '0088FF',
  string: 'A5FF90',
  number: 'FF628C',
  identifier: '9EFFFF',
  lineHighlight: '1F4662',
  selection: '0050A4',
  operator: 'FF9D00',
  cursor: 'FFC600',
  bracket: 'FFC600',
);

final ayuMirageDef = _def(
  id: 'ayu-mirage',
  dark: true,
  bg: '1F2430',
  fg: 'CBCCC6',
  keyword: 'FFA759',
  comment: '5C6773',
  string: 'BAE67E',
  number: 'FFCC66',
  identifier: '73D0FF',
  lineHighlight: '242936',
  selection: '34455A',
  operator: 'F29E74',
  bracket: 'FFCC66',
);

final ayuLightDef = _def(
  id: 'ayu-light',
  dark: false,
  bg: 'FAFAFA',
  fg: '5C6773',
  keyword: 'FA8D3E',
  comment: 'ABB0B6',
  string: '86B300',
  number: 'A37ACC',
  identifier: '399EE6',
  lineHighlight: 'F0F0F0',
  selection: 'D1E4F4',
  operator: 'ED9366',
  bracket: 'FA8D3E',
);

final blulocoLightDef = _def(
  id: 'bluloco-light',
  dark: false,
  bg: 'F9F9F9',
  fg: '383A42',
  keyword: '0098DD',
  comment: 'A0A1A7',
  string: '23974A',
  number: 'CE33C0',
  identifier: '7A82DA',
  lineHighlight: 'EFEFEF',
  selection: 'D2E7FF',
  operator: 'DF631C',
  bracket: '0098DD',
);
