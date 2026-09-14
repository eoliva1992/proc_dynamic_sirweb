/// Cambio aplicado al documento pero **pendiente de que el usuario decida**.
///
/// Escribir y dar por bueno es lo que hace inutilizable a un asistente: si se
/// equivoca en un tramo, el usuario tiene que rehacerlo a mano. El modelo de
/// revisión es el de VS Code: el cambio se ve ya aplicado en su contexto, y
/// cada tramo se acepta o se descarta por separado.
///
/// La parte delicada es la contabilidad. Al descartar un tramo el documento
/// cambia de longitud, así que **todos los tramos posteriores se desplazan**.
/// Esta clase lleva esa cuenta para que el editor solo tenga que escribir el
/// rango que se le indique.
library;

import 'line_diff.dart';

/// Un tramo pendiente de decisión.
class PendingHunk {
  /// Líneas que había antes, y que vuelven si se descarta.
  final List<String> originalLines;

  /// Primera línea del tramo en el documento **actual** (base 1).
  int startLine;

  /// Cuántas líneas ocupa ahora. Cero si el tramo fue un borrado.
  int lineCount;

  /// Ya se aceptó o se descartó.
  bool resolved;

  PendingHunk({
    required this.originalLines,
    required this.startLine,
    required this.lineCount,
    this.resolved = false,
  });

  /// Última línea del tramo, inclusive. Igual a [startLine] menos uno cuando
  /// el tramo fue un borrado y no ocupa ninguna.
  int get endLine => startLine + lineCount - 1;

  bool get esBorrado => lineCount == 0;
  bool get esInsercion => originalLines.isEmpty;
}

/// Orden que hay que escribir en el editor para descartar un tramo.
class RevertEdit {
  /// Primera línea a sustituir (base 1).
  final int startLine;

  /// Última línea a sustituir, inclusive. Menor que [startLine] si no hay que
  /// borrar nada, solo insertar.
  final int endLine;

  /// Lo que debe quedar en su lugar.
  final List<String> lines;

  const RevertEdit(this.startLine, this.endLine, this.lines);

  @override
  String toString() => 'RevertEdit($startLine-$endLine, ${lines.length}L)';
}

/// Conjunto de tramos que Copilot escribió y aún no se han confirmado.
class PendingChange {
  final List<PendingHunk> hunks;

  PendingChange(this.hunks);

  /// Construye el pendiente a partir del diff que se acaba de aplicar.
  ///
  /// [offset] traslada los índices cuando el diff se calculó sobre una
  /// selección en vez de sobre el documento entero.
  factory PendingChange.fromDiff(
    List<DiffHunk> diff,
    List<String> originalLines, {
    int offset = 0,
  }) {
    final hunks = <PendingHunk>[];
    var desplazamiento = 0;
    for (final h in diff) {
      final inicio = h.startOld + desplazamiento + offset;
      hunks.add(
        PendingHunk(
          originalLines: originalLines.sublist(h.startOld, h.endOld),
          startLine: inicio + 1,
          lineCount: h.added,
        ),
      );
      desplazamiento += h.added - h.removed;
    }
    return PendingChange(hunks);
  }

  /// Tramos que siguen esperando decisión.
  List<PendingHunk> get pendientes =>
      hunks.where((h) => !h.resolved).toList(growable: false);

  bool get todoResuelto => pendientes.isEmpty;
  int get total => hunks.length;
  int get restantes => pendientes.length;

  /// Acepta el tramo [index]: el documento ya está como debe, solo se marca.
  void aceptar(int index) => hunks[index].resolved = true;

  /// Acepta todos los tramos que quedaban.
  void aceptarTodo() {
    for (final h in hunks) {
      h.resolved = true;
    }
  }

  /// Descarta el tramo [index] y devuelve la edición que hay que escribir.
  ///
  /// Devuelve `null` si ya estaba resuelto. Ajusta la posición de los tramos
  /// posteriores, porque el documento acaba de cambiar de longitud.
  RevertEdit? descartar(int index) {
    final h = hunks[index];
    if (h.resolved) return null;

    final edit = RevertEdit(h.startLine, h.endLine, h.originalLines);
    final delta = h.originalLines.length - h.lineCount;

    h
      ..lineCount = h.originalLines.length
      ..resolved = true;

    for (var i = index + 1; i < hunks.length; i++) {
      hunks[i].startLine += delta;
    }
    return edit;
  }

  /// Descarta todo lo que quede, de abajo arriba.
  ///
  /// El orden importa: revertir desde el final evita que cada edición
  /// invalide las posiciones de las siguientes.
  List<RevertEdit> descartarTodo() {
    final edits = <RevertEdit>[];
    for (var i = hunks.length - 1; i >= 0; i--) {
      final e = descartar(i);
      if (e != null) edits.add(e);
    }
    return edits;
  }

  /// Rangos que hay que resaltar: los que aún esperan decisión.
  List<(int, int)> get rangosPendientes => [
    for (final h in pendientes)
      if (h.lineCount > 0) (h.startLine, h.endLine),
  ];

  /// Índice del siguiente tramo sin resolver a partir de [desde], dando la
  /// vuelta al llegar al final.
  int? siguientePendiente(int desde) {
    if (todoResuelto) return null;
    for (var i = 0; i < hunks.length; i++) {
      final idx = (desde + i) % hunks.length;
      if (!hunks[idx].resolved) return idx;
    }
    return null;
  }
}
