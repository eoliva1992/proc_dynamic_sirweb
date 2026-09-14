/// Selección activa en el editor Monaco.
///
/// Sirve para dos cosas que el chat necesita distinguir con precisión:
/// mandar a Copilot **solo el fragmento marcado** en vez del documento
/// entero, y poder decir en el chip de contexto *qué* se mandó, con el mismo
/// formato `archivo:línea` que usa VS Code.
class EditorSelection {
  /// Primera línea seleccionada (base 1, como en Monaco).
  final int startLine;

  /// Última línea seleccionada (base 1, inclusive).
  final int endLine;

  /// Texto seleccionado tal cual, sin recortar.
  final String text;

  const EditorSelection({
    required this.startLine,
    required this.endLine,
    required this.text,
  });

  /// Reconstruye la selección desde el JSON que devuelve el webview.
  ///
  /// Devuelve `null` ante cualquier forma inesperada: es un puente hacia
  /// JavaScript, así que no se puede confiar en los tipos.
  static EditorSelection? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final texto = json['text'];
    if (texto is! String || texto.trim().isEmpty) return null;
    final desde = (json['startLine'] as num?)?.toInt();
    final hasta = (json['endLine'] as num?)?.toInt();
    if (desde == null || hasta == null || desde < 1) return null;
    return EditorSelection(
      startLine: desde,
      endLine: hasta < desde ? desde : hasta,
      text: texto,
    );
  }

  /// Número de líneas que abarca.
  int get lineCount => endLine - startLine + 1;

  /// Etiqueta corta para el chip: `DR_REGLA:112` o `DR_REGLA:112-140`.
  ///
  /// Es el formato de VS Code, y comunica de un vistazo si se envía una línea
  /// o un bloque entero.
  String label(String archivo) {
    final base = archivo.trim().isEmpty ? 'editor' : archivo.trim();
    return startLine == endLine
        ? '$base:$startLine'
        : '$base:$startLine-$endLine';
  }

  @override
  String toString() => 'EditorSelection($startLine-$endLine, ${text.length}c)';
}
