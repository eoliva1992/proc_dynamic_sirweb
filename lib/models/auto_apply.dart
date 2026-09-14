/// Decide si un bloque de código de Copilot puede escribirse **solo** en el
/// documento, sin que el usuario lo revise antes.
///
/// Aplicar automáticamente es cómodo, pero el modelo a veces responde con un
/// fragmento ilustrativo o con elisiones (`-- ...`, `/* resto igual */`). Si
/// eso reemplazara el procedimiento entero se perdería código. Como el cambio
/// siempre es deshacible con Ctrl+Z, el criterio no busca certeza absoluta:
/// busca descartar los casos en los que el bloque **evidentemente** no es el
/// contenido final.
library;

import 'chat_message.dart';

/// Marcas de que el modelo omitió parte del código.
///
/// Se comprueban línea a línea: unos puntos suspensivos dentro de un literal
/// o de un comentario descriptivo son legítimos, pero una línea que *solo*
/// contiene la elisión indica que falta código.
final _elision = RegExp(
  r'^\s*(?:--+|/\*+|//+)?\s*(?:\.{3}|\u2026)'
  r'|^\s*(?:\.{3}|\u2026)\s*$',
);

/// Palabras con las que empieza una unidad PL/SQL completa.
final _inicioUnidad = RegExp(
  r'^\s*(?:CREATE\s+OR\s+REPLACE|CREATE|DECLARE|BEGIN)\b',
  caseSensitive: false,
);

/// Resultado del análisis de un bloque de código.
enum AutoApplyDecision {
  /// Reemplaza el documento entero.
  replaceDocument,

  /// Reemplaza solo el fragmento seleccionado.
  replaceSelection,

  /// No se aplica solo: el usuario decide con el botón.
  ask,
}

/// ¿Se puede aplicar [code] automáticamente?
///
/// [haySeleccion] cambia el listón. Con selección, el usuario ya acotó el
/// alcance y basta con que el bloque no venga recortado. Sin selección se
/// sustituye el procedimiento completo, así que además se exige que el bloque
/// parezca una unidad PL/SQL entera.
AutoApplyDecision decideAutoApply(String code, {required bool haySeleccion}) {
  final limpio = code.trim();
  if (limpio.isEmpty) return AutoApplyDecision.ask;

  // Un bloque con elisiones no es el contenido final, mande lo que mande el
  // resto del criterio.
  for (final linea in limpio.split('\n')) {
    if (_elision.hasMatch(linea)) return AutoApplyDecision.ask;
  }

  if (haySeleccion) return AutoApplyDecision.replaceSelection;

  // Sin selección, solo se reemplaza el documento si el bloque abre como una
  // unidad completa. Un `IF ... END IF;` suelto es un fragmento.
  if (!_inicioUnidad.hasMatch(limpio)) return AutoApplyDecision.ask;

  // Y debe cerrar: un `BEGIN` sin `END` es una respuesta truncada.
  if (!RegExp(
    r'\bEND\b\s*;?\s*/?\s*$',
    caseSensitive: false,
  ).hasMatch(limpio)) {
    return AutoApplyDecision.ask;
  }

  return AutoApplyDecision.replaceDocument;
}

/// Último bloque de código de una respuesta, o `null` si no hay ninguno.
///
/// Se coge el último y no el primero porque, cuando el modelo enseña el
/// «antes» y el «después», el resultado final va siempre al cierre.
String? ultimoBloqueDeCodigo(String content) {
  final bloques = parseMarkdownBlocks(
    content,
  ).where((b) => b.isCode && b.text.trim().isNotEmpty).toList();
  return bloques.isEmpty ? null : bloques.last.text;
}
