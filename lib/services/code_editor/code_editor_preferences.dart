import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuración de preferencias visuales y de comportamiento del editor de código.
///
/// Encapsula las opciones configurables por el usuario y su persistencia en
/// [SharedPreferences], desacoplando esta responsabilidad del widget UI.
class CodeEditorPreferences extends ChangeNotifier {
  static final CodeEditorPreferences instance = CodeEditorPreferences._();

  CodeEditorPreferences._();

  factory CodeEditorPreferences() => instance;

  bool minimap = true;
  bool lineNumbers = true;
  bool folding = true;
  bool readOnly = false;
  double fontSize = 14.0;
  bool wordWrap = false;
  bool renderWhitespace = false;
  bool bracketPairColorization = true;
  bool stickyScroll = true;
  bool smoothScrolling = false;
  bool mouseWheelZoom = false;
  bool formatOnPaste = false;
  bool quickSuggestions = true;
  bool parameterHints = true;
  bool hover = true;
  bool links = true;
  bool occurrencesHighlight = true;
  bool contextMenu = true;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Carga las preferencias guardadas desde [SharedPreferences].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    minimap = prefs.getBool('editor_minimap') ?? true;
    lineNumbers = prefs.getBool('editor_lineNumbers') ?? true;
    folding = prefs.getBool('editor_folding') ?? true;
    fontSize = prefs.getDouble('editor_fontSize') ?? 14.0;
    wordWrap = prefs.getBool('editor_wordWrap') ?? false;
    renderWhitespace = prefs.getBool('editor_renderWhitespace') ?? false;
    bracketPairColorization =
        prefs.getBool('editor_bracketPairColorization') ?? true;
    stickyScroll = prefs.getBool('editor_stickyScroll') ?? true;
    smoothScrolling = prefs.getBool('editor_smoothScrolling') ?? false;
    mouseWheelZoom = prefs.getBool('editor_mouseWheelZoom') ?? false;
    formatOnPaste = prefs.getBool('editor_formatOnPaste') ?? false;
    quickSuggestions = prefs.getBool('editor_quickSuggestions') ?? true;
    parameterHints = prefs.getBool('editor_parameterHints') ?? true;
    hover = prefs.getBool('editor_hover') ?? true;
    links = prefs.getBool('editor_links') ?? true;
    occurrencesHighlight = prefs.getBool('editor_occurrencesHighlight') ?? true;
    contextMenu = prefs.getBool('editor_contextMenu') ?? true;
    _loaded = true;
    notifyListeners();
  }

  /// Restablece todos los valores a los valores por defecto recomendados y los guarda.
  Future<void> resetAll() async {
    minimap = true;
    lineNumbers = true;
    folding = true;
    readOnly = false;
    fontSize = 14.0;
    wordWrap = false;
    renderWhitespace = false;
    bracketPairColorization = true;
    stickyScroll = true;
    smoothScrolling = false;
    mouseWheelZoom = false;
    formatOnPaste = false;
    quickSuggestions = true;
    parameterHints = true;
    hover = true;
    links = true;
    occurrencesHighlight = true;
    contextMenu = true;
    await save();
    notifyListeners();
  }

  /// Persiste los valores actuales en [SharedPreferences].
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('editor_minimap', minimap),
      prefs.setBool('editor_lineNumbers', lineNumbers),
      prefs.setBool('editor_folding', folding),
      prefs.setDouble('editor_fontSize', fontSize),
      prefs.setBool('editor_wordWrap', wordWrap),
      prefs.setBool('editor_renderWhitespace', renderWhitespace),
      prefs.setBool('editor_bracketPairColorization', bracketPairColorization),
      prefs.setBool('editor_stickyScroll', stickyScroll),
      prefs.setBool('editor_smoothScrolling', smoothScrolling),
      prefs.setBool('editor_mouseWheelZoom', mouseWheelZoom),
      prefs.setBool('editor_formatOnPaste', formatOnPaste),
      prefs.setBool('editor_quickSuggestions', quickSuggestions),
      prefs.setBool('editor_parameterHints', parameterHints),
      prefs.setBool('editor_hover', hover),
      prefs.setBool('editor_links', links),
      prefs.setBool('editor_occurrencesHighlight', occurrencesHighlight),
      prefs.setBool('editor_contextMenu', contextMenu),
    ]);
  }
}
