/// Diff por líneas entre el documento actual y el que propone Copilot.
///
/// Reemplazar el documento entero funciona, pero borra y reescribe hasta lo
/// que no cambió: el resaltado marca todo el fichero, se pierde el plegado y
/// no hay forma de ver *qué* tocó el modelo. Calculando el diff se aplican
/// solo los tramos distintos, que es lo que hace legible el cambio.
library;

/// Un tramo que hay que sustituir.
///
/// Reemplaza las líneas `[startOld, endOld)` del documento original por
/// [lines]. Una inserción pura tiene `startOld == endOld`; un borrado puro,
/// [lines] vacío.
class DiffHunk {
  final int startOld;
  final int endOld;
  final List<String> lines;

  const DiffHunk(this.startOld, this.endOld, this.lines);

  bool get isInsert => startOld == endOld;
  bool get isDelete => lines.isEmpty && endOld > startOld;

  /// Líneas que se eliminan del original.
  int get removed => endOld - startOld;

  /// Líneas que se escriben.
  int get added => lines.length;

  @override
  String toString() => 'DiffHunk($startOld,$endOld,+${lines.length})';

  @override
  bool operator ==(Object other) =>
      other is DiffHunk &&
      other.startOld == startOld &&
      other.endOld == endOld &&
      other.lines.length == lines.length &&
      List.generate(
        lines.length,
        (i) => lines[i] == other.lines[i],
      ).every((x) => x);

  @override
  int get hashCode => Object.hash(startOld, endOld, lines.length);
}

/// Tamaño máximo de la región central para la que se calcula el LCS.
///
/// El LCS es O(n·m) en tiempo y memoria. Con los prefijos y sufijos comunes
/// recortados la región restante suele ser diminuta, pero si el modelo
/// reescribe de arriba abajo se degrada a un único tramo en vez de bloquear
/// la interfaz.
const int kMaxLcsLines = 600;

/// Calcula los tramos que convierten [viejo] en [nuevo].
///
/// Devuelve una lista vacía si son idénticos.
List<DiffHunk> diffLines(List<String> viejo, List<String> nuevo) {
  // 1) Prefijo común: la mayoría de las ediciones de un modelo conservan la
  //    cabecera intacta, así que esto ya recorta casi todo el trabajo.
  var ini = 0;
  final maxIni = viejo.length < nuevo.length ? viejo.length : nuevo.length;
  while (ini < maxIni && viejo[ini] == nuevo[ini]) {
    ini++;
  }

  // 2) Sufijo común, sin invadir el prefijo.
  var finViejo = viejo.length;
  var finNuevo = nuevo.length;
  while (finViejo > ini &&
      finNuevo > ini &&
      viejo[finViejo - 1] == nuevo[finNuevo - 1]) {
    finViejo--;
    finNuevo--;
  }

  if (ini == finViejo && ini == finNuevo) return const [];

  final medioViejo = viejo.sublist(ini, finViejo);
  final medioNuevo = nuevo.sublist(ini, finNuevo);

  // 3) Región central demasiado grande: un solo tramo. Sigue siendo mejor
  //    que reemplazar el documento, porque respeta prefijo y sufijo.
  if (medioViejo.length > kMaxLcsLines || medioNuevo.length > kMaxLcsLines) {
    return [DiffHunk(ini, finViejo, medioNuevo)];
  }

  return _hunksDesdeLcs(medioViejo, medioNuevo, ini);
}

/// Convierte el emparejamiento LCS en tramos contiguos.
List<DiffHunk> _hunksDesdeLcs(
  List<String> viejo,
  List<String> nuevo,
  int offset,
) {
  final n = viejo.length;
  final m = nuevo.length;

  // Tabla LCS clásica: lcs[i][j] = longitud común de viejo[i..] y nuevo[j..].
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = viejo[i] == nuevo[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final hunks = <DiffHunk>[];
  var i = 0;
  var j = 0;
  // Tramo abierto: desde dónde y qué líneas nuevas lleva acumuladas.
  int? abiertoDesde;
  var acumuladas = <String>[];

  void cerrar(int hastaViejo) {
    if (abiertoDesde == null) return;
    hunks.add(
      DiffHunk(abiertoDesde! + offset, hastaViejo + offset, acumuladas),
    );
    abiertoDesde = null;
    acumuladas = <String>[];
  }

  while (i < n && j < m) {
    if (viejo[i] == nuevo[j]) {
      cerrar(i);
      i++;
      j++;
    } else {
      abiertoDesde ??= i;
      // Se avanza por el lado que conserva más coincidencias futuras.
      if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        i++;
      } else {
        acumuladas.add(nuevo[j]);
        j++;
      }
    }
  }

  if (i < n || j < m) {
    abiertoDesde ??= i;
    acumuladas.addAll(nuevo.sublist(j));
    i = n;
  }
  cerrar(i);

  return hunks;
}

/// Rangos de líneas **del documento resultante** que quedaron tocados.
///
/// Sirven para resaltar solo lo que escribió Copilot. Se devuelven en base 1,
/// que es la que usa Monaco, y con el par (primera, última) inclusive.
List<(int, int)> lineasTocadas(List<DiffHunk> hunks) {
  final rangos = <(int, int)>[];
  var desplazamiento = 0;
  for (final h in hunks) {
    final inicio = h.startOld + desplazamiento;
    if (h.added > 0) rangos.add((inicio + 1, inicio + h.added));
    desplazamiento += h.added - h.removed;
  }
  return rangos;
}

/// Trocea un texto en líneas sin inventar una final de más.
List<String> aLineas(String texto) => texto.split('\n');
