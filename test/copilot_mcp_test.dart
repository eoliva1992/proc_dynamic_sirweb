import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/services/copilot_cli_service.dart';

void main() {
  group('lista blanca de servidores MCP', () {
    test('sqlcl y mcp-sirweb están permitidos', () {
      expect(CopilotCliService.isMcpAllowed('sqlcl'), isTrue);
      expect(CopilotCliService.isMcpAllowed('mcp-sirweb'), isTrue);
    });

    test('tolera las variantes de escritura del nombre', () {
      // El nombre lo pone el usuario en su mcp-config.json.
      for (final n in const [
        'mcp_sirweb',
        'MCP-Sirweb',
        'mcp sirweb',
        'SQLcl',
      ]) {
        expect(
          CopilotCliService.isMcpAllowed(n),
          isTrue,
          reason: '«$n» debería estar permitido',
        );
      }
    });

    test('cualquier otro servidor queda fuera', () {
      // Es una lista blanca: lo que no está, no entra.
      for (final n in const [
        'filesystem',
        'github',
        'playwright',
        'postgres',
        'sirweb-escritura',
      ]) {
        expect(
          CopilotCliService.isMcpAllowed(n),
          isFalse,
          reason: '«$n» no debería estar permitido',
        );
      }
    });

    test('el nombre vacío no cuela', () {
      expect(CopilotCliService.isMcpAllowed(''), isFalse);
    });
  });

  group('el agente nunca escribe en la base de datos', () {
    test('las herramientas de alta y modificación están denegadas', () {
      for (final t in const [
        'crear_procedimiento',
        'actualizar_procedimiento',
        'cambiar_estado_procedimiento',
        'compile_object_ddl',
      ]) {
        expect(
          CopilotCliService.deniedDbWriteTools,
          contains(t),
          reason: '«$t» modifica Oracle y debe estar denegada',
        );
      }
    });

    test('las de ejecución también, aunque hagan rollback', () {
      // Hacen ROLLBACK, pero consumen sesión y toman locks: no son inocuas.
      for (final t in const [
        'ejecutar_procedimiento_dinamico',
        'ejecutar_subprograma',
        'ejecutar_llamada',
      ]) {
        expect(CopilotCliService.deniedDbWriteTools, contains(t));
      }
    });

    test('sqlcl no puede ejecutar SQL libre', () {
      expect(CopilotCliService.deniedDbWriteTools, contains('run-sqlcl'));
    });

    test('las herramientas de solo consulta siguen disponibles', () {
      // Denegar de más dejaría al modo Agente sin poder investigar nada.
      for (final t in const [
        'obtener_procedimiento',
        'listar_procedimientos',
        'get_table_columns',
        'info_evento',
        'buscar_usos_procedimiento',
      ]) {
        expect(
          CopilotCliService.deniedDbWriteTools,
          isNot(contains(t)),
          reason: '«$t» solo lee y debe seguir permitida',
        );
      }
    });
  });

  group('el prompt prohíbe tocar la base de datos', () {
    final service = CopilotCliService.instance;

    test('la prohibición viaja con la pregunta', () {
      final prompt = service.buildPrompt(question: 'Optimiza esto');
      expect(prompt, contains('PROHIBIDO'));
      expect(prompt, contains('modificar la base de datos'));
      expect(prompt, contains('editor'));
    });

    test('el modo Agente limita los MCP a consultar', () {
      final prompt = service.buildPrompt(
        question: '¿Qué tablas usa?',
        mode: CopilotChatMode.agent,
      );
      expect(prompt, contains('SOLO para consultar'));
      expect(prompt, contains('sqlcl'));
      expect(prompt, contains('mcp-sirweb'));
      // Consultar no puede convertirse en el resultado del turno.
      expect(prompt, contains('termina con el PL/SQL para el editor'));
    });

    test('el modo Plan sigue sin aplicar cambios', () {
      final prompt = service.buildPrompt(
        question: 'Cambia el cálculo',
        mode: CopilotChatMode.plan,
      );
      expect(prompt, contains('No apliques'));
    });
  });
}
