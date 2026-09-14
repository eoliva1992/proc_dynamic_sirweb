import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/edit_blocks.dart';

/// Compone una respuesta con el formato anclado.
String respuestaCon(List<(String, String)> pares) => pares
    .map(
      (p) =>
          '$kBuscarMarker\n${p.$1}\n$kSepararMarker\n${p.$2}\n'
          '$kReemplazarMarker',
    )
    .join('\n\n');

void main() {
  group('parseEditBlocks', () {
    test('extrae una edición', () {
      final b = parseEditBlocks(respuestaCon([('  v := 1;', '  v := 2;')]));
      expect(b, hasLength(1));
      expect(b.first.buscar, '  v := 1;');
      expect(b.first.reemplazar, '  v := 2;');
    });

    test('extrae varias en orden', () {
      final b = parseEditBlocks(respuestaCon([('a', 'A'), ('b', 'B')]));
      expect(b.map((e) => e.buscar), ['a', 'b']);
    });

    test('conserva el multilínea', () {
      final b = parseEditBlocks(
        respuestaCon([('IF x THEN\n  NULL;\nEND IF;', 'NULL;')]),
      );
      expect(b.first.buscar.split('\n'), hasLength(3));
    });

    test('una respuesta sin el formato devuelve lista vacía', () {
      // Permite caer al camino de bloque completo.
      expect(
        parseEditBlocks('Aquí tienes:\n```sql\nBEGIN NULL; END;\n```'),
        isEmpty,
      );
    });

    test('tolera texto alrededor de los bloques', () {
      final r =
          'Explico el cambio:\n\n'
          '${respuestaCon([('a', 'A')])}\n\nY ya está.';
      expect(parseEditBlocks(r), hasLength(1));
    });
  });

  group('applyEditBlocks', () {
    const doc = 'BEGIN\n  v := 1;\n  w := 9;\nEND;';

    test('sustituye el ancla', () {
      final r = applyEditBlocks(doc, [
        const EditBlock('  v := 1;', '  v := 2;'),
      ]);
      expect(r.todoOk, isTrue);
      expect(r.texto, 'BEGIN\n  v := 2;\n  w := 9;\nEND;');
    });

    test('aplica varias ediciones en cadena', () {
      final r = applyEditBlocks(doc, const [
        EditBlock('  v := 1;', '  v := 2;'),
        EditBlock('  w := 9;', '  w := 8;'),
      ]);
      expect(r.aplicadas, 2);
      expect(r.texto, 'BEGIN\n  v := 2;\n  w := 8;\nEND;');
    });

    test('un ancla inexistente se reporta y no rompe el resto', () {
      // Fallar en voz alta es el objetivo: mejor eso que escribir a ciegas.
      final r = applyEditBlocks(doc, const [
        EditBlock('  no existe;', 'x'),
        EditBlock('  w := 9;', '  w := 8;'),
      ]);
      expect(r.aplicadas, 1);
      expect(r.errores, hasLength(1));
      expect(r.errores.first.motivo, EditFailure.noEncontrado);
      expect(r.texto, contains('w := 8;'));
    });

    test('un ancla ambigua no se aplica', () {
      // Elegir «la primera» sería una moneda al aire.
      const repetido = 'BEGIN\n  NULL;\n  NULL;\nEND;';
      final r = applyEditBlocks(repetido, const [EditBlock('  NULL;', '  x;')]);
      expect(r.aplicadas, 0);
      expect(r.errores.first.motivo, EditFailure.ambiguo);
      expect(r.texto, repetido);
    });

    test('encuentra el ancla aunque cambie la sangría', () {
      // El modelo reproduce el código de memoria y desliza los espacios.
      final r = applyEditBlocks(doc, const [EditBlock('v := 1;', '  v := 2;')]);
      expect(r.aplicadas, 1);
      expect(r.texto, contains('v := 2;'));
    });

    test('el ancla vacía añade al final', () {
      final r = applyEditBlocks('BEGIN', const [EditBlock('', 'END;')]);
      expect(r.texto, 'BEGIN\nEND;');
    });

    test('sin bloques no hay cambios ni éxito', () {
      final r = applyEditBlocks(doc, const []);
      expect(r.texto, doc);
      expect(r.todoOk, isFalse);
    });
  });

  group('numerarLineas', () {
    test('numera desde 1 y alinea a la derecha', () {
      final n = numerarLineas(List.generate(10, (i) => 'l$i').join('\n'));
      expect(n.split('\n').first, ' 1| l0');
      expect(n.split('\n').last, '10| l9');
    });

    test('conserva el contenido de cada línea', () {
      expect(numerarLineas('  sangrado'), '1|   sangrado');
    });
  });
}
