import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/services/copilot_cli_service.dart';

void main() {
  final service = CopilotCliService.instance;

  group('el entregable es siempre el editor', () {
    test('el contrato viaja en el primer turno', () {
      final prompt = service.buildPrompt(question: 'Optimiza el cursor');
      expect(prompt, contains('TU ENTREGABLE ES SIEMPRE UNA EDICIÓN'));
      expect(prompt, contains('editor de procedimientos dinámicos'));
    });

    test('y también en los turnos de seguimiento', () {
      // Regresión: el contrato estaba dentro de `if (!isFollowUp)`, así que a
      // partir de la segunda pregunta el modelo perdía el marco y volvía a
      // recomendar cambios contra la base de datos.
      final prompt = service.buildPrompt(
        question: 'Y ahora quita el bucle',
        isFollowUp: true,
      );
      expect(prompt, contains('TU ENTREGABLE ES SIEMPRE UNA EDICIÓN'));
      expect(prompt, contains('PROHIBIDO'));
    });

    test('prohíbe explícitamente proponer operaciones sobre la base', () {
      final prompt = service.buildPrompt(question: 'Corrige esto');
      for (final v in const [
        'UPDATE',
        'CREATE OR REPLACE',
        'ALTER',
        'SQL Developer',
      ]) {
        expect(
          prompt,
          contains(v),
          reason: 'debe nombrar «$v» entre lo prohibido',
        );
      }
    });

    test('el preámbulo caro solo va en el primer turno', () {
      // La identidad no cambia y la sesión de la CLI la conserva: repetirla
      // gastaría presupuesto de línea de comandos sin aportar nada.
      final primero = service.buildPrompt(question: 'Hola');
      final siguiente = service.buildPrompt(
        question: 'Sigue',
        isFollowUp: true,
      );
      expect(primero, contains('PROCEDIMIENTODINAMICO'));
      expect(siguiente, isNot(contains('PROCEDIMIENTODINAMICO')));
    });
  });

  group('anclaje al procedimiento en curso', () {
    test('el nombre y el ambiente viajan también en seguimiento', () {
      final prompt = service.buildPrompt(
        question: 'Sigue',
        procedimiento: 'DR_MI_REGLA',
        ambiente: 'Desa',
        isFollowUp: true,
      );
      expect(prompt, contains('DR_MI_REGLA'));
      expect(prompt, contains('Desa'));
    });
  });

  group('los modos refuerzan el mismo contrato', () {
    test('Agente: consultar es un medio, no el entregable', () {
      final prompt = service.buildPrompt(
        question: '¿Qué tablas usa?',
        mode: CopilotChatMode.agent,
      );
      expect(prompt, contains('SOLO para consultar'));
      expect(prompt, contains('termina con el PL/SQL para el editor'));
    });

    test('Plan: los pasos describen el código, no tareas sobre la base', () {
      final prompt = service.buildPrompt(
        question: 'Cambia el cálculo',
        mode: CopilotChatMode.plan,
      );
      expect(prompt, contains('c\u00f3digo del editor'));
      expect(prompt, contains('no tareas sobre la'));
    });
  });
}
