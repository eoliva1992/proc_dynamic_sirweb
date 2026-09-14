import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/auto_apply.dart';

void main() {
  group('decideAutoApply · sin selección', () {
    test('una unidad PL/SQL completa reemplaza el documento', () {
      final d = decideAutoApply('BEGIN\n  NULL;\nEND;', haySeleccion: false);
      expect(d, AutoApplyDecision.replaceDocument);
    });

    test('acepta DECLARE y CREATE OR REPLACE', () {
      for (final src in const [
        'DECLARE\n  v NUMBER;\nBEGIN\n  NULL;\nEND;',
        'CREATE OR REPLACE PROCEDURE p IS\nBEGIN\n  NULL;\nEND;',
      ]) {
        expect(
          decideAutoApply(src, haySeleccion: false),
          AutoApplyDecision.replaceDocument,
          reason: src,
        );
      }
    });

    test('un fragmento suelto no reemplaza el documento', () {
      // Sustituir toda la regla por un IF perdería el resto del código.
      final d = decideAutoApply(
        'IF v_total > 0 THEN\n  NULL;\nEND IF;',
        haySeleccion: false,
      );
      expect(d, AutoApplyDecision.ask);
    });

    test('un BEGIN sin END está truncado', () {
      final d = decideAutoApply('BEGIN\n  NULL;', haySeleccion: false);
      expect(d, AutoApplyDecision.ask);
    });
  });

  group('decideAutoApply · con selección', () {
    test('cualquier bloque íntegro reemplaza la selección', () {
      // El usuario ya acotó el alcance, así que no hace falta que el bloque
      // sea una unidad completa.
      final d = decideAutoApply(
        'IF v_total > 0 THEN\n  NULL;\nEND IF;',
        haySeleccion: true,
      );
      expect(d, AutoApplyDecision.replaceSelection);
    });
  });

  group('decideAutoApply · elisiones', () {
    test('detecta el código recortado por el modelo', () {
      for (final src in const [
        'BEGIN\n  -- ...\n  NULL;\nEND;',
        'BEGIN\n  ...\nEND;',
        'BEGIN\n  /* ... resto igual ... */\n  NULL;\nEND;',
        'BEGIN\n  \u2026\nEND;',
      ]) {
        expect(
          decideAutoApply(src, haySeleccion: false),
          AutoApplyDecision.ask,
          reason: 'debería descartar: $src',
        );
      }
    });

    test('la elisión manda incluso con selección', () {
      final d = decideAutoApply('foo;\n-- ...\nbar;', haySeleccion: true);
      expect(d, AutoApplyDecision.ask);
    });

    test('los puntos dentro de una frase no son elisión', () {
      // Un comentario legítimo no debe bloquear la aplicación automática.
      final d = decideAutoApply(
        'BEGIN\n  -- calcula la prima. Ver nota 3.\n  NULL;\nEND;',
        haySeleccion: false,
      );
      expect(d, AutoApplyDecision.replaceDocument);
    });
  });

  test('el bloque vacío nunca se aplica', () {
    expect(decideAutoApply('   ', haySeleccion: true), AutoApplyDecision.ask);
  });

  group('ultimoBloqueDeCodigo', () {
    test('devuelve el último bloque, que es el resultado final', () {
      // Cuando el modelo enseña «antes» y «después», el bueno es el último.
      final c = ultimoBloqueDeCodigo(
        'Antes:\n```sql\nviejo\n```\nDespués:\n```sql\nnuevo\n```',
      );
      expect(c, 'nuevo');
    });

    test('null si la respuesta no trae código', () {
      expect(ultimoBloqueDeCodigo('Solo texto explicativo.'), isNull);
    });

    test('ignora los bloques vacíos', () {
      expect(ultimoBloqueDeCodigo('```sql\n\n```'), isNull);
    });
  });
}
