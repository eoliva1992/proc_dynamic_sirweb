import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/chat_plan.dart';

void main() {
  group('parsePlan · lista numerada', () {
    test('extrae los pasos numerados', () {
      final plan = parsePlan('''
Voy a hacer lo siguiente:

1. Revisar el cursor principal
2. Sustituir el bucle por FORALL
3. Añadir el manejo de excepciones
''');
      expect(plan.length, 3);
      expect(plan.steps.first.title, 'Revisar el cursor principal');
      expect(plan.steps.last.title, 'Añadir el manejo de excepciones');
    });

    test('quita el marcado del título', () {
      final plan = parsePlan('1. Usar **BULK COLLECT**\n2. Cerrar el `cursor`');
      expect(plan.steps[0].title, 'Usar BULK COLLECT');
      expect(plan.steps[1].title, 'Cerrar el cursor');
    });

    test('se queda con el título cuando el paso trae detalle', () {
      final plan = parsePlan(
        '1. Optimizar el cursor: hay que reescribirlo con BULK COLLECT '
        'porque hoy hace un round-trip por fila\n'
        '2. Probar el resultado',
      );
      expect(plan.steps.first.title, 'Optimizar el cursor');
    });

    test('recorta los títulos desmedidos', () {
      final plan = parsePlan('1. ${'x' * 200}\n2. otro');
      expect(plan.steps.first.title.length, lessThanOrEqualTo(90));
      expect(plan.steps.first.title, endsWith('…'));
    });
  });

  // El modo Plan pide «un plan numerado», pero el modelo no siempre obedece.
  // Estos formatos aparecen a menudo y antes dejaban la barra sin salir.
  group('parsePlan · formatos alternativos', () {
    test('encabezados numerados', () {
      final plan = parsePlan('''
## 1. Revisar el cursor
Texto del paso.

## 2. Reescribir con FORALL
Más texto.
''');
      expect(plan.length, 2);
      expect(plan.steps.first.title, 'Revisar el cursor');
      expect(plan.steps.last.title, 'Reescribir con FORALL');
    });

    test('encabezados con la palabra Paso o Step', () {
      final plan = parsePlan('### Paso 1: Analizar\n\n### Paso 2 - Corregir');
      expect(plan.length, 2);
      expect(plan.steps.first.title, 'Analizar');
      expect(plan.steps.last.title, 'Corregir');
    });

    test('casillas de tarea', () {
      final plan = parsePlan('- [ ] Analizar el cursor\n- [ ] Reescribirlo');
      expect(plan.length, 2);
      expect(plan.steps.first.title, 'Analizar el cursor');
    });

    test('lista con viñetas como último recurso', () {
      // En modo Plan la respuesta *es* el plan: una lista suelta sigue siendo
      // accionable aunque no venga numerada.
      final plan = parsePlan('- Analizar el cursor\n- Reescribirlo');
      expect(plan.length, 2);
    });

    test('la lista numerada gana a los encabezados', () {
      final plan = parsePlan('## 1. Titular\n\n1. Uno real\n2. Dos real');
      expect(plan.steps.first.title, 'Uno real');
    });
  });

  group('parsePlan · lo que no es un plan', () {
    test('un solo punto numerado no es un plan', () {
      final plan = parsePlan('Ojo:\n\n1. Este cursor no cierra');
      expect(plan.isEmpty, isTrue);
    });

    test('el texto sin listas ni encabezados no produce plan', () {
      expect(parsePlan('Esto solo es una explicación larga.').isEmpty, isTrue);
    });

    test('ignora la numeración dentro de un bloque de código', () {
      final plan = parsePlan('```sql\n1. no es paso\n2. tampoco\n```');
      expect(plan.isEmpty, isTrue);
    });

    test('los encabezados sin numerar no son pasos', () {
      expect(parsePlan('## Contexto\n\n## Conclusión').isEmpty, isTrue);
    });
  });

  test('los títulos nunca traen saltos de línea', () {
    final plan = parsePlan('1. Un paso\n2. Otro paso');
    expect(plan.steps.every((s) => !s.title.contains('\n')), isTrue);
  });
}
