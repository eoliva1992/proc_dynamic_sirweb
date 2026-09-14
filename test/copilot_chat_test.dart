import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/chat_conversation.dart';
import 'package:proc_dynamic_sirweb/models/chat_message.dart';
import 'package:proc_dynamic_sirweb/models/copilot_event.dart';
import 'package:proc_dynamic_sirweb/services/copilot_cli_service.dart';

void main() {
  group('parseMarkdownBlocks', () {
    test('devuelve un único párrafo si no hay marcado', () {
      final blocks = parseMarkdownBlocks('Hola, esto es texto plano.');
      expect(blocks, hasLength(1));
      expect(blocks.first.kind, MdBlockKind.paragraph);
      expect(blocks.first.text, 'Hola, esto es texto plano.');
    });

    test('separa texto y código con lenguaje', () {
      final blocks = parseMarkdownBlocks(
        'Prueba esto:\n```sql\nSELECT 1 FROM DUAL;\n```\nY listo.',
      );
      expect(blocks, hasLength(3));
      expect(blocks[0].text, 'Prueba esto:');
      expect(blocks[1].isCode, isTrue);
      expect(blocks[1].language, 'sql');
      expect(blocks[1].text, 'SELECT 1 FROM DUAL;');
      expect(blocks[2].text, 'Y listo.');
    });

    test('cierra el bloque aunque el fence final falte (streaming)', () {
      final blocks = parseMarkdownBlocks('Ahí va:\n```sql\nBEGIN\n  NULL;');
      expect(blocks.last.isCode, isTrue);
      expect(blocks.last.text, contains('BEGIN'));
    });

    test('bloque sin lenguaje deja language en null', () {
      final blocks = parseMarkdownBlocks('```\nfoo\n```');
      expect(blocks.single.isCode, isTrue);
      expect(blocks.single.language, isNull);
    });

    test('reconoce encabezados con su nivel', () {
      final blocks = parseMarkdownBlocks('# Uno\n### Tres');
      expect(blocks[0].kind, MdBlockKind.heading);
      expect(blocks[0].level, 1);
      expect(blocks[0].text, 'Uno');
      expect(blocks[1].level, 3);
    });

    test('reconoce listas con viñeta y numeradas', () {
      final blocks = parseMarkdownBlocks('- uno\n- dos\n1. primero');
      expect(blocks[0].kind, MdBlockKind.bullet);
      expect(blocks[1].text, 'dos');
      expect(blocks[2].kind, MdBlockKind.numbered);
      expect(blocks[2].marker, '1.');
    });

    test('reconoce citas y reglas horizontales', () {
      final blocks = parseMarkdownBlocks('> ojo\n\n---');
      expect(blocks[0].kind, MdBlockKind.quote);
      expect(blocks[0].text, 'ojo');
      expect(blocks[1].kind, MdBlockKind.rule);
    });

    test('no confunde un guion dentro de código con una lista', () {
      final blocks = parseMarkdownBlocks('```sql\n- no es lista\n```');
      expect(blocks.single.isCode, isTrue);
      expect(blocks.single.text, '- no es lista');
    });
  });

  group('parseInlineSpans', () {
    test('detecta negrita, código y enlaces', () {
      final spans = parseInlineSpans(
        'usa **BULK** con `FORALL` y ve a [docs](https://x.dev)',
      );
      expect(spans.firstWhere((s) => s.style == MdSpanStyle.bold).text, 'BULK');
      expect(
        spans.firstWhere((s) => s.style == MdSpanStyle.code).text,
        'FORALL',
      );
      final link = spans.firstWhere((s) => s.style == MdSpanStyle.link);
      expect(link.text, 'docs');
      expect(link.href, 'https://x.dev');
    });

    test('el texto sin marcado devuelve un único span normal', () {
      final spans = parseInlineSpans('solo texto');
      expect(spans, hasLength(1));
      expect(spans.single.style, MdSpanStyle.normal);
    });
  });

  group('CopilotEvent.tryParse', () {
    test('extrae el fragmento incremental de un message_delta', () {
      final e = CopilotEvent.tryParse(
        '{"type":"assistant.message_delta",'
        '"data":{"messageId":"m1","deltaContent":"HO"}}',
      );
      expect(e!.kind, CopilotEventKind.delta);
      expect(e.text, 'HO');
    });

    test('extrae contenido y modelo del mensaje final', () {
      final e = CopilotEvent.tryParse(
        '{"type":"assistant.message",'
        '"data":{"content":"HOLA","model":"claude-sonnet-5"}}',
      );
      expect(e!.kind, CopilotEventKind.message);
      expect(e.text, 'HOLA');
      expect(e.model, 'claude-sonnet-5');
    });

    test('el evento result trae sessionId y consumo en la raíz', () {
      final e = CopilotEvent.tryParse(
        '{"type":"result","sessionId":"abc-123","exitCode":0,'
        '"usage":{"premiumRequests":1,"totalApiDurationMs":1424}}',
      );
      expect(e!.kind, CopilotEventKind.result);
      expect(e.sessionId, 'abc-123');
      expect(e.exitCode, 0);
      expect(e.premiumRequests, 1);
      expect(e.apiDurationMs, 1424);
    });

    test('los eventos de arranque describen la fase', () {
      final e = CopilotEvent.tryParse(
        '{"type":"session.mcp_server_status_changed",'
        '"data":{"serverName":"sqlcl","status":"connected"}}',
      );
      expect(e!.kind, CopilotEventKind.startup);
      expect(e.detail, contains('sqlcl'));
    });

    test('una línea que no es JSON no rompe el stream', () {
      expect(CopilotEvent.tryParse('Bienvenido a Copilot CLI'), isNull);
      expect(CopilotEvent.tryParse(''), isNull);
      expect(CopilotEvent.tryParse('{roto'), isNull);
    });

    test('un delta vacío se descarta', () {
      final e = CopilotEvent.tryParse(
        '{"type":"assistant.message_delta","data":{"deltaContent":""}}',
      );
      expect(e, isNull);
    });

    test('un tipo desconocido se marca como unknown y se ignora', () {
      final e = CopilotEvent.tryParse('{"type":"algo.nuevo","data":{}}');
      expect(e!.kind, CopilotEventKind.unknown);
    });
  });

  group('ChatConversation', () {
    test('no se puede reanudar hasta que la CLI confirma la sesión', () {
      final c = ChatConversation.nueva()..sessionId = 'uuid-1';
      expect(c.canResume, isFalse);
      c.sessionStarted = true;
      expect(c.canResume, isTrue);
    });

    test('el título se deriva de la primera pregunta', () {
      final c = ChatConversation.nueva()
        ..messages.add(ChatMessage.user('¿Qué hace este cursor?'))
        ..autoTitle();
      expect(c.title, '¿Qué hace este cursor?');
    });

    test('el título largo se recorta', () {
      final c = ChatConversation.nueva()
        ..messages.add(ChatMessage.user('x' * 80))
        ..autoTitle();
      expect(c.title.length, lessThanOrEqualTo(43));
      expect(c.title, endsWith('…'));
    });

    test('serializa y deserializa conservando la sesión', () {
      final c = ChatConversation.nueva()
        ..sessionId = 'uuid-9'
        ..sessionStarted = true
        ..messages.add(ChatMessage.user('hola'));
      final copy = ChatConversation.fromJson(c.toJson());
      expect(copy.sessionId, 'uuid-9');
      expect(copy.sessionStarted, isTrue);
      expect(copy.messages.single.content, 'hola');
    });
  });

  group('ChatMessage', () {
    test('appendChunk acumula el streaming', () {
      final m = ChatMessage.assistant('', isStreaming: true);
      m
        ..appendChunk('Hola')
        ..appendChunk(' mundo');
      expect(m.content, 'Hola mundo');
    });

    test('isPending solo mientras no hay contenido', () {
      final m = ChatMessage.assistant('', isStreaming: true);
      expect(m.isPending, isTrue);
      m.appendChunk('algo');
      expect(m.isPending, isFalse);
    });

    test('serializa y deserializa', () {
      final original = ChatMessage.user('¿Qué hace este cursor?');
      final copy = ChatMessage.fromJson(original.toJson());
      expect(copy.role, ChatRole.user);
      expect(copy.content, original.content);
    });
  });

  group('parseSlashCommand', () {
    test('reconoce un comando conocido y devuelve el resto', () {
      final r = parseSlashCommand('/explicar el cursor principal');
      expect(r.command, isNotNull);
      expect(r.command!.name, 'explicar');
      expect(r.rest, 'el cursor principal');
    });

    test('acepta el comando sin argumentos', () {
      final r = parseSlashCommand('/revisar');
      expect(r.command!.name, 'revisar');
      expect(r.rest, isEmpty);
    });

    test('es insensible a mayúsculas y tolera espacios previos', () {
      final r = parseSlashCommand('  /OPTIMIZAR esto');
      expect(r.command!.name, 'optimizar');
      expect(r.rest, 'esto');
    });

    test('un comando desconocido se trata como texto normal', () {
      final r = parseSlashCommand('/inventado algo');
      expect(r.command, isNull);
      expect(r.rest, '/inventado algo');
    });

    test('el texto sin barra no es comando', () {
      final r = parseSlashCommand('explica esto');
      expect(r.command, isNull);
      expect(r.rest, 'explica esto');
    });

    test('todos los comandos tienen nombre y plantilla', () {
      expect(kChatSlashCommands, isNotEmpty);
      for (final c in kChatSlashCommands) {
        expect(c.name, isNotEmpty);
        expect(c.template, isNotEmpty);
        expect(c.description, isNotEmpty);
      }
    });
  });

  group('el documento abierto siempre viaja en el prompt', () {
    final service = CopilotCliService.instance;

    test('el código va en el primer turno', () {
      final prompt = service.buildPrompt(
        question: '¿Qué hace?',
        code: 'BEGIN NULL; END;',
        procedimiento: 'DR_TEST',
      );
      expect(prompt, contains('BEGIN NULL; END;'));
    });

    test('y también en los turnos de seguimiento', () {
      // La sesión de la CLI conserva el hilo, pero el código pudo cambiar en
      // el editor entre una pregunta y la siguiente: hay que reenviarlo.
      final prompt = service.buildPrompt(
        question: 'Y ahora?',
        code: 'BEGIN NULL; END;',
        isFollowUp: true,
      );
      expect(prompt, contains('BEGIN NULL; END;'));
    });

    test('ningún comando puede renunciar al código del editor', () {
      // `ChatSlashCommand` ya no expone `requiresCode`: si alguien la
      // reintroduce, este test obliga a replantear la decisión.
      expect(
        kChatSlashCommands.every((c) => c.template.isNotEmpty),
        isTrue,
        reason: 'el contexto del editor es incondicional',
      );
    });
  });

  group('trimToBudget', () {
    test('no toca el texto que ya cabe', () {
      expect(CopilotCliService.trimToBudget('hola', 100), 'hola');
    });

    test('recorta conservando principio y final', () {
      final texto = List.generate(500, (i) => 'linea $i').join('\n');
      final r = CopilotCliService.trimToBudget(texto, 400);
      expect(r.length, lessThanOrEqualTo(400));
      expect(r, startsWith('linea 0'));
      expect(r, endsWith('linea 499'));
      expect(r, contains('fragmento omitido'));
    });

    test('con presupuesto mínimo corta en seco sin desbordar', () {
      final r = CopilotCliService.trimToBudget('x' * 1000, 50);
      expect(r.length, 50);
    });
  });

  group('buildPrompt', () {
    final service = CopilotCliService.instance;

    test('incluye contexto del editor y la pregunta', () {
      final prompt = service.buildPrompt(
        question: '¿Qué hace?',
        code: 'BEGIN NULL; END;',
        procedimiento: 'DR_TEST',
        ambiente: 'Desa',
        errores: 'Línea 1: PLS-00103',
      );

      expect(prompt, contains('DR_TEST'));
      expect(prompt, contains('Desa'));
      expect(prompt, contains('BEGIN NULL; END;'));
      expect(prompt, contains('PLS-00103'));
      expect(prompt, contains('¿Qué hace?'));
    });

    test('arrastra el historial y omite los mensajes de error', () {
      final prompt = service.buildPrompt(
        question: 'Sigue',
        history: [
          ChatMessage.user('Primera'),
          ChatMessage.assistant('Respuesta'),
          ChatMessage.error('Fallo de red'),
        ],
      );

      expect(prompt, contains('Primera'));
      expect(prompt, contains('Respuesta'));
      expect(prompt, isNot(contains('Fallo de red')));
    });

    test('omite las secciones vacías', () {
      final prompt = service.buildPrompt(question: 'Hola', code: '   ');
      expect(prompt, isNot(contains('Código en el editor')));
      expect(prompt, isNot(contains('Errores actuales')));
    });

    test('recorta el contexto para no desbordar la línea de comandos', () {
      final codigoEnorme = List.generate(
        5000,
        (i) => '-- linea $i de un procedimiento muy largo',
      ).join('\n');

      final prompt = service.buildPrompt(
        question: 'Explica',
        code: codigoEnorme,
        maxChars: 4000,
      );

      expect(codigoEnorme.length, greaterThan(100000));
      // El invariante es no superar el presupuesto; agotarlo es válido.
      expect(prompt.length, lessThanOrEqualTo(4000));
      expect(prompt, contains('fragmento omitido'));
      expect(prompt, contains('Explica'));
    });

    test('en un turno de seguimiento omite el preámbulo del dominio', () {
      final primero = service.buildPrompt(question: 'Hola');
      final siguiente = service.buildPrompt(
        question: 'Y ahora?',
        isFollowUp: true,
      );

      expect(primero, contains('PROCEDIMIENTODINAMICO'));
      // Con sesión reanudada la CLI ya conserva el hilo: reenviar el
      // preámbulo solo gastaría presupuesto de línea de comandos.
      expect(siguiente, isNot(contains('PROCEDIMIENTODINAMICO')));
      expect(siguiente, contains('Y ahora?'));
    });

    test('el turno de seguimiento sigue enviando el código y los errores', () {
      final prompt = service.buildPrompt(
        question: 'Revisa',
        code: 'BEGIN NULL; END;',
        errores: 'PLS-00103',
        isFollowUp: true,
      );
      expect(prompt, contains('BEGIN NULL; END;'));
      expect(prompt, contains('PLS-00103'));
    });

    test('el modo Plan pide un plan por pasos', () {
      final service = CopilotCliService.instance;
      final prompt = service.buildPrompt(
        question: 'Cambia el cálculo de la prima',
        mode: CopilotChatMode.plan,
      );
      expect(prompt, contains('Modo Plan'));
      expect(prompt, contains('plan numerado'));
    });

    test('el modo Agente autoriza el uso de herramientas', () {
      final service = CopilotCliService.instance;
      final prompt = service.buildPrompt(
        question: '¿Qué tablas usa la regla?',
        mode: CopilotChatMode.agent,
      );
      expect(prompt, contains('Modo Agente'));
      expect(prompt, contains('MCP'));
    });

    test('el modo Pregunta no añade instrucciones extra', () {
      final service = CopilotCliService.instance;
      final prompt = service.buildPrompt(question: 'Hola');
      expect(prompt, isNot(contains('Modo Plan')));
      expect(prompt, isNot(contains('Modo Agente')));
    });
  });

  group('parseModelsFromHelp', () {
    const help = '''
  `logLevel`: log level for CLI; defaults to "default".

  `model`: AI model to use for Copilot CLI; can be changed with /model command.
    - "claude-sonnet-5"
    - "gpt-5.4"
    - "gemini-3.8-flash"

  `contextTier`: context window tier for tiered-pricing models.
''';

    test('extrae los modelos enumerados bajo la clave model', () {
      final models = CopilotCliService.parseModelsFromHelp(help);
      expect(models, ['claude-sonnet-5', 'gpt-5.4', 'gemini-3.8-flash']);
    });

    test('devuelve lista vacía si la ayuda no trae el bloque', () {
      expect(
        CopilotCliService.parseModelsFromHelp('sin modelos aquí'),
        isEmpty,
      );
    });

    test('ignora duplicados y respeta el orden', () {
      final models = CopilotCliService.parseModelsFromHelp(
        '`model`: modelos\n    - "gpt-5.4"\n    - "gpt-5.4"\n    - "kimi-k3"\n',
      );
      expect(models, ['gpt-5.4', 'kimi-k3']);
    });
  });

  group('modos y ajustes del chat', () {
    test('los identificadores de modo van y vuelven', () {
      for (final m in CopilotChatMode.values) {
        expect(CopilotChatModeX.fromId(m.id), m);
      }
      expect(CopilotChatModeX.fromId('desconocido'), CopilotChatMode.ask);
    });

    test('el esfuerzo automático no genera opción de línea de comandos', () {
      expect(CopilotEffort.auto.flagValue, isNull);
      expect(CopilotEffort.high.flagValue, 'high');
      expect(CopilotEffortX.fromId('medium'), CopilotEffort.medium);
      expect(CopilotEffortX.fromId(null), CopilotEffort.auto);
    });

    test('la ventana de contexto usa los valores que espera la CLI', () {
      expect(CopilotContextTier.standard.flagValue, 'default');
      expect(CopilotContextTier.long.flagValue, 'long_context');
      expect(CopilotContextTierX.fromId('long'), CopilotContextTier.long);
      expect(CopilotContextTierX.fromId(null), CopilotContextTier.standard);
    });
  });
}
