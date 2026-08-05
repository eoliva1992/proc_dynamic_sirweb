import 'package:flutter_monaco/flutter_monaco.dart';

const oracleDarkTheme = MonacoTheme('oracle-dark');
const oracleLightTheme = MonacoTheme('oracle-light');

const oracleDark = MonacoThemeDefinition(
  id: 'oracle-dark',
  base: MonacoBaseTheme.vsDark,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: 'C586C0', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '6A9955',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'CE9178'),
    MonacoThemeRule(token: 'number', foreground: 'B5CEA8'),
    MonacoThemeRule(token: 'identifier', foreground: '9CDCFE'),
    MonacoThemeRule(token: 'operator', foreground: 'D4D4D4'),
    MonacoThemeRule(token: 'delimiter', foreground: 'BBBBBB'),
  ],
  colors: {
    'editor.background': '#1A1A2E',
    'editor.foreground': '#E0E0E0',
    'editorLineNumber.foreground': '#555577',
    'editorLineNumber.activeForeground': '#AAAACC',
    'editor.lineHighlightBackground': '#16213E',
    'editor.selectionBackground': '#264F78',
    'editorCursor.foreground': '#AEAFAD',
    'editor.inactiveSelectionBackground': '#1E3A5F',
    'editorIndentGuide.background1': '#2D2D4E',
    'editorBracketMatch.background': '#0D3A58',
    'editorBracketMatch.border': '#1A7AC7',
  },
);

const oracleLight = MonacoThemeDefinition(
  id: 'oracle-light',
  base: MonacoBaseTheme.vs,
  rules: [
    MonacoThemeRule(token: 'keyword', foreground: '0000CD', fontStyle: 'bold'),
    MonacoThemeRule(
      token: 'comment',
      foreground: '008000',
      fontStyle: 'italic',
    ),
    MonacoThemeRule(token: 'string', foreground: 'A31515'),
    MonacoThemeRule(token: 'number', foreground: '098658'),
    MonacoThemeRule(token: 'identifier', foreground: '001080'),
    MonacoThemeRule(token: 'operator', foreground: '3B3B3B'),
    MonacoThemeRule(token: 'delimiter', foreground: '666666'),
  ],
  colors: {
    'editor.background': '#FAFAFA',
    'editor.foreground': '#1E1E1E',
    'editorLineNumber.foreground': '#AAAAAA',
    'editor.lineHighlightBackground': '#F5F5F5',
    'editor.selectionBackground': '#ADD6FF',
    'editorCursor.foreground': '#333333',
    'editorBracketMatch.background': '#BCEAF1',
    'editorBracketMatch.border': '#0078D4',
  },
);
