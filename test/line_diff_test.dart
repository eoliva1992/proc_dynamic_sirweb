import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/line_diff.dart';

/// Aplica los tramos para comprobar que reconstruyen el texto esperado.
List<String> aplicar(List<String> viejo, List<DiffHunk> hunks) {
  final r = List<String>.from(viejo);
  // De atrás hacia delante, para que los índices no se desplacen.
  for (final h in hunks.reversed) {
    r.replaceRange(h.startOld, h.endOld, h.lines);
  }
  return r;
}

void main() {
  group('diffLines', () {
    test('textos idénticos no producen tramos', () {
      expect(diffLines(['a', 'b'], ['a', 'b']), isEmpty);
    });

    test('cambiar una línea toca solo esa línea', () {
      // Es el caso que motiva todo esto: no reescribir el documento entero.
      final h = diffLines(
        ['BEGIN', '  v := 1;', 'END;'],
        ['BEGIN', '  v := 2;', 'END;'],
      );
      expect(h, hasLength(1));
      expect(h.first.startOld, 1);
      expect(h.first.endOld, 2);
      expect(h.first.lines, ['  v := 2;']);
    });

    test('insertar una línea no borra ninguna', () {
      final h = diffLines(['a', 'c'], ['a', 'b', 'c']);
      expect(h, hasLength(1));
      expect(h.first.isInsert, isTrue);
      expect(h.first.lines, ['b']);
    });

    test('borrar una línea no escribe ninguna', () {
      final h = diffLines(['a', 'b', 'c'], ['a', 'c']);
      expect(h, hasLength(1));
      expect(h.first.isDelete, isTrue);
      expect(h.first.removed, 1);
    });

    test('dos cambios separados dan dos tramos', () {
      // Si diera uno solo, se reescribiría también el bloque intermedio.
      final viejo = ['a', 'X', 'c', 'd', 'Y', 'f'];
      final nuevo = ['a', '1', 'c', 'd', '2', 'f'];
      final h = diffLines(viejo, nuevo);
      expect(h, hasLength(2));
      expect(aplicar(viejo, h), nuevo);
    });

    test('reconstruye el texto en casos variados', () {
      final casos = <(List<String>, List<String>)>[
        (['a', 'b', 'c'], ['c', 'b', 'a']),
        ([], ['a', 'b']),
        (['a', 'b'], []),
        (['a'], ['a', 'a', 'a']),
        (['x', 'y', 'z'], ['x', 'z']),
        (['uno', 'dos', 'tres'], ['uno', 'DOS', 'tres', 'cuatro']),
      ];
      for (final (viejo, nuevo) in casos) {
        expect(
          aplicar(viejo, diffLines(viejo, nuevo)),
          nuevo,
          reason: '$viejo -> $nuevo',
        );
      }
    });

    test('conserva prefijo y sufijo comunes', () {
      // 100 líneas iguales arriba y abajo, una distinta en medio.
      final viejo = [
        ...List.generate(100, (i) => 'pre$i'),
        'medio viejo',
        ...List.generate(100, (i) => 'post$i'),
      ];
      final nuevo = [
        ...List.generate(100, (i) => 'pre$i'),
        'medio nuevo',
        ...List.generate(100, (i) => 'post$i'),
      ];
      final h = diffLines(viejo, nuevo);
      expect(h, hasLength(1));
      expect(h.first.startOld, 100);
      expect(h.first.endOld, 101);
    });

    test('una reescritura enorme degrada a un solo tramo sin colgarse', () {
      // Por encima del tope del LCS no se calcula la tabla: se sustituye la
      // region central de una vez.
      final viejo = List.generate(kMaxLcsLines + 50, (i) => 'v$i');
      final nuevo = List.generate(kMaxLcsLines + 50, (i) => 'n$i');
      final h = diffLines(viejo, nuevo);
      expect(h, hasLength(1));
      expect(aplicar(viejo, h), nuevo);
    });
  });

  group('lineasTocadas', () {
    test('devuelve el rango resultante en base 1', () {
      final h = diffLines(
        ['BEGIN', '  v := 1;', 'END;'],
        ['BEGIN', '  v := 2;', 'END;'],
      );
      expect(lineasTocadas(h), [(2, 2)]);
    });

    test('desplaza los rangos cuando se insertan líneas antes', () {
      final viejo = ['a', 'b', 'c'];
      final nuevo = ['a', 'nueva', 'b', 'C'];
      final rangos = lineasTocadas(diffLines(viejo, nuevo));
      // La inserción va en la línea 2 y el cambio de «c» cae ya en la 4.
      expect(rangos.first.$1, 2);
      expect(rangos.last.$2, 4);
    });

    test('un borrado puro no marca ninguna línea', () {
      expect(lineasTocadas(diffLines(['a', 'b', 'c'], ['a', 'c'])), isEmpty);
    });
  });
}
