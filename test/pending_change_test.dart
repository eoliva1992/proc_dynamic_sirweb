import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/line_diff.dart';
import 'package:proc_dynamic_sirweb/models/pending_change.dart';

/// Simula el editor: aplica una reversión sobre las líneas del documento.
void aplicar(List<String> doc, RevertEdit e) {
  // `endLine < startLine` significa insertar sin borrar nada.
  final desde = e.startLine - 1;
  final hasta = e.endLine >= e.startLine ? e.endLine : desde;
  doc.replaceRange(desde, hasta, e.lines);
}

void main() {
  // Dos cambios **separados** por una línea intacta: así son dos tramos que
  // el usuario puede decidir por separado.
  final original = ['BEGIN', '  v := 1;', '  x := 0;', '  w := 9;', 'END;'];
  final propuesto = ['BEGIN', '  v := 2;', '  x := 0;', '  w := 8;', 'END;'];

  PendingChange nuevoPendiente() =>
      PendingChange.fromDiff(diffLines(original, propuesto), original);

  group('construcción desde el diff', () {
    test('un tramo por cada cambio separado', () {
      final p = nuevoPendiente();
      expect(p.total, 2);
      expect(p.restantes, 2);
      expect(p.todoResuelto, isFalse);
    });

    test('los cambios adyacentes forman un solo tramo', () {
      // Decidir línea a línea sobre un bloque contiguo sería absurdo: es un
      // único cambio conceptual. VS Code los agrupa igual.
      final p = PendingChange.fromDiff(
        diffLines(
          ['BEGIN', '  a := 1;', '  b := 2;', 'END;'],
          ['BEGIN', '  a := 9;', '  b := 8;', 'END;'],
        ),
        ['BEGIN', '  a := 1;', '  b := 2;', 'END;'],
      );
      expect(p.total, 1);
      expect(p.hunks.single.lineCount, 2);
    });

    test('las líneas originales quedan guardadas para poder volver', () {
      final p = nuevoPendiente();
      expect(p.hunks.first.originalLines, ['  v := 1;']);
    });

    test('las posiciones son las del documento ya modificado', () {
      final p = nuevoPendiente();
      expect(p.hunks[0].startLine, 2);
      expect(p.hunks[1].startLine, 4);
    });
  });

  group('aceptar', () {
    test('aceptar no cambia el documento, solo marca', () {
      final p = nuevoPendiente()..aceptar(0);
      expect(p.restantes, 1);
      expect(p.hunks[0].resolved, isTrue);
    });

    test('aceptar todo resuelve el conjunto', () {
      final p = nuevoPendiente()..aceptarTodo();
      expect(p.todoResuelto, isTrue);
    });
  });

  group('descartar', () {
    test('descartar un tramo devuelve el original de ESE tramo', () {
      final doc = List<String>.from(propuesto);
      final p = nuevoPendiente();
      aplicar(doc, p.descartar(0)!);
      // Vuelve la primera línea; la otra conserva el cambio.
      expect(doc, ['BEGIN', '  v := 1;', '  x := 0;', '  w := 8;', 'END;']);
    });

    test('descartar todo restaura el documento entero', () {
      final doc = List<String>.from(propuesto);
      final p = nuevoPendiente();
      for (final e in p.descartarTodo()) {
        aplicar(doc, e);
      }
      expect(doc, original);
      expect(p.todoResuelto, isTrue);
    });

    test('descartar dos veces el mismo tramo no hace nada', () {
      final p = nuevoPendiente();
      expect(p.descartar(0), isNotNull);
      expect(p.descartar(0), isNull);
    });
  });

  group('contabilidad al cambiar la longitud', () {
    // El caso que rompe una implementación ingenua: si un tramo descartado
    // devuelve más o menos líneas, los siguientes se desplazan.
    final viejo = ['a', 'X', 'b', 'Y', 'c'];
    final nuevo = ['a', 'N1', 'N2', 'N3', 'b', 'M', 'c'];

    test('descartar el primero recoloca el segundo', () {
      final doc = List<String>.from(nuevo);
      final p = PendingChange.fromDiff(diffLines(viejo, nuevo), viejo);
      expect(p.total, 2);

      aplicar(doc, p.descartar(0)!);
      expect(doc, ['a', 'X', 'b', 'M', 'c']);

      // Tras encoger el documento, el segundo tramo debe apuntar a «M».
      aplicar(doc, p.descartar(1)!);
      expect(doc, viejo);
    });

    test('descartar de abajo arriba también restaura', () {
      final doc = List<String>.from(nuevo);
      final p = PendingChange.fromDiff(diffLines(viejo, nuevo), viejo);
      aplicar(doc, p.descartar(1)!);
      aplicar(doc, p.descartar(0)!);
      expect(doc, viejo);
    });

    test('mezclar aceptar y descartar', () {
      final doc = List<String>.from(nuevo);
      final p = PendingChange.fromDiff(diffLines(viejo, nuevo), viejo);
      p.aceptar(0);
      aplicar(doc, p.descartar(1)!);
      // Se queda el primer cambio y se revierte el segundo.
      expect(doc, ['a', 'N1', 'N2', 'N3', 'b', 'Y', 'c']);
      expect(p.todoResuelto, isTrue);
    });
  });

  group('resaltado y navegación', () {
    test('solo se resalta lo que sigue pendiente', () {
      final p = nuevoPendiente();
      expect(p.rangosPendientes, hasLength(2));
      p.aceptar(0);
      expect(p.rangosPendientes, hasLength(1));
    });

    test('la navegación da la vuelta y salta lo resuelto', () {
      final p = nuevoPendiente();
      expect(p.siguientePendiente(0), 0);
      p.aceptar(0);
      expect(p.siguientePendiente(0), 1);
      p.aceptar(1);
      expect(p.siguientePendiente(0), isNull);
    });
  });
}

