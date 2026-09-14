/// Ediciones ancladas: el formato que hace precisa la escritura.
///
/// Un modelo que responde con el fichero entero obliga a adivinar dónde
/// encajarlo, y si recorta algo se pierde. El formato anclado invierte la
/// carga: el modelo dice **qué texto exacto** hay que sustituir y por cuál, de
/// modo que la aplicación es determinista y **falla en voz alta** cuando el
/// ancla ya no existe, en vez de escribir en el sitio equivocado.
///
/// Es el mismo principio que usan las herramientas de edición de los agentes
/// de IDE (`replace_string_in_file` y equivalentes).
library;

/// Marcadores del bloque, deliberadamente largos para que no aparezcan por
/// accidente dentro de un PL/SQL.
const kBuscarMarker = '<<<<<<< BUSCAR';
const kSepararMarker = '=======';
const kReemplazarMarker = '>>>>>>> REEMPLAZAR';

/// Una sustitución anclada.
class EditBlock {
  /// Texto que debe existir tal cual en el documento.
  final String buscar;

  /// Texto que lo sustituye.
  final String reemplazar;

  const EditBlock(this.buscar, this.reemplazar);

  @override
  bool operator ==(Object other) =>
      other is EditBlock &&
      other.buscar == buscar &&
      other.reemplazar == reemplazar;

  @override
  int get hashCode => Object.hash(buscar, reemplazar);

  @override
  String toString() => 'EditBlock(${buscar.length}c -> ${reemplazar.length}c)';
}

/// Por qué no se pudo aplicar una edición.
enum EditFailure {
  /// El texto buscado no aparece en el documento.
  noEncontrado,

  /// Aparece más de una vez: aplicarlo sería adivinar cuál.
  ambiguo,
}

class EditError {
  final EditBlock block;
  final EditFailure motivo;

  const EditError(this.block, this.motivo);

  String get mensaje => switch (motivo) {
    EditFailure.noEncontrado => 'No se encontró el texto a sustituir',
    EditFailure.ambiguo => 'El texto a sustituir aparece varias veces',
  };
}

/// Resultado de aplicar un conjunto de ediciones.
class EditResult {
  final String texto;
  final int aplicadas;
  final List<EditError> errores;

  const EditResult(this.texto, this.aplicadas, this.errores);

  bool get todoOk => errores.isEmpty && aplicadas > 0;
}

final _bloque = RegExp(
  '$kBuscarMarker\\r?\\n(.*?)\\r?\\n$kSepararMarker\\r?\\n(.*?)\\r?\\n?'
  '$kReemplazarMarker',
  dotAll: true,
);

/// Extrae las ediciones ancladas de una respuesta.
///
/// Devuelve lista vacía si la respuesta no usa el formato, para que el panel
/// pueda caer al camino de bloque completo.
List<EditBlock> parseEditBlocks(String respuesta) {
  return [
    for (final m in _bloque.allMatches(respuesta))
      EditBlock(m.group(1) ?? '', m.group(2) ?? ''),
  ];
}

/// Aplica [bloques] sobre [documento].
///
/// Las sustituciones se aplican **en orden** y sobre el resultado de la
/// anterior, igual que una secuencia de ediciones reales. Un bloque que falla
/// no aborta el resto: se informa y se sigue, porque la mayoría de las veces
/// las demás ediciones son válidas y útiles por sí solas.
EditResult applyEditBlocks(String documento, List<EditBlock> bloques) {
  var texto = documento;
  var aplicadas = 0;
  final errores = <EditError>[];

  for (final b in bloques) {
    // Insertar en documento vacío o añadir al final: un ancla vacía significa
    // «no hay nada que buscar».
    if (b.buscar.isEmpty) {
      texto = texto.isEmpty ? b.reemplazar : '$texto\n${b.reemplazar}';
      aplicadas++;
      continue;
    }

    final primera = texto.indexOf(b.buscar);
    if (primera == -1) {
      final relajado = _buscarIgnorandoSangria(texto, b.buscar);
      if (relajado == null) {
        errores.add(EditError(b, EditFailure.noEncontrado));
        continue;
      }
      texto = texto.replaceRange(relajado.$1, relajado.$2, b.reemplazar);
      aplicadas++;
      continue;
    }

    // Ambiguo: sustituir «la primera» sería una moneda al aire.
    if (texto.indexOf(b.buscar, primera + 1) != -1) {
      errores.add(EditError(b, EditFailure.ambiguo));
      continue;
    }

    texto = texto.replaceRange(
      primera,
      primera + b.buscar.length,
      b.reemplazar,
    );
    aplicadas++;
  }

  return EditResult(texto, aplicadas, errores);
}

/// Busca [aguja] comparando las líneas sin su sangría.
///
/// El modelo reproduce el código de memoria y a menudo cambia los espacios de
/// indentación. Exigir coincidencia exacta haría fallar ediciones correctas,
/// así que se reintenta ignorando la sangría; el rango devuelto sigue siendo
/// el del documento real.
(int, int)? _buscarIgnorandoSangria(String texto, String aguja) {
  final lineasTexto = texto.split('\n');
  final lineasAguja = aguja.split('\n');
  if (lineasAguja.isEmpty || lineasAguja.length > lineasTexto.length) {
    return null;
  }

  String norm(String s) => s.trim();
  final objetivo = lineasAguja.map(norm).toList();

  int? encontrada;
  for (var i = 0; i + objetivo.length <= lineasTexto.length; i++) {
    var casa = true;
    for (var j = 0; j < objetivo.length; j++) {
      if (norm(lineasTexto[i + j]) != objetivo[j]) {
        casa = false;
        break;
      }
    }
    if (!casa) continue;
    // Igual que en el camino exacto: si hay dos, no se elige.
    if (encontrada != null) return null;
    encontrada = i;
  }
  if (encontrada == null) return null;

  var inicio = 0;
  for (var i = 0; i < encontrada; i++) {
    inicio += lineasTexto[i].length + 1;
  }
  var fin = inicio;
  for (var j = 0; j < objetivo.length; j++) {
    fin +=
        lineasTexto[encontrada + j].length + (j == objetivo.length - 1 ? 0 : 1);
  }
  return (inicio, fin);
}

/// Numera las líneas del código que se manda al modelo.
///
/// Ver los números le permite referirse a un punto concreto y reproducir el
/// ancla con exactitud, que es justo lo que necesita el formato anclado.
String numerarLineas(String codigo) {
  final lineas = codigo.split('\n');
  final ancho = lineas.length.toString().length;
  return [
    for (var i = 0; i < lineas.length; i++)
      '${(i + 1).toString().padLeft(ancho)}| ${lineas[i]}',
  ].join('\n');
}
