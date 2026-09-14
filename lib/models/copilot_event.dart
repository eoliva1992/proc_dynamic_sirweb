import 'dart:convert';

/// Tipos de evento que emite `copilot --output-format json` (JSONL).
///
/// El protocolo real observado en la CLI 1.0.83 es, en orden:
///
/// ```text
/// session.mcp_server_status_changed   ← arranque de servidores MCP
/// session.mcp_servers_loaded
/// session.skills_loaded
/// session.custom_agents_updated
/// session.tools_updated               ← trae el modelo efectivo
/// user.message
/// assistant.turn_start
/// assistant.message_start             ← messageId
/// assistant.message_delta             ← deltaContent (streaming token a token)
/// assistant.message                   ← contenido final + outputTokens
/// assistant.turn_end
/// assistant.idle
/// result                              ← sessionId, exitCode, usage
/// ```
enum CopilotEventKind {
  /// Progreso de arranque (MCP, skills, agentes). Alimenta el indicador de
  /// "preparando…" mientras la CLI todavía no ha llamado al modelo.
  startup,

  /// Comienza un turno del asistente.
  turnStart,

  /// Fragmento incremental de la respuesta.
  delta,

  /// Mensaje completo del asistente (llega al final del turno).
  message,

  /// El agente solicita ejecutar una herramienta.
  toolStart,

  /// Resultado de una herramienta.
  toolEnd,

  /// Fin de la ejecución: trae `sessionId`, `exitCode` y consumo.
  result,

  /// Evento no contemplado; se ignora sin romper el parseo.
  unknown,
}

/// Un evento del stream JSONL ya normalizado.
class CopilotEvent {
  final CopilotEventKind kind;

  /// Texto incremental ([CopilotEventKind.delta]) o completo
  /// ([CopilotEventKind.message]).
  final String? text;

  /// Modelo efectivo que resolvió la CLI (p. ej. `claude-sonnet-5`).
  final String? model;

  /// Identificador de sesión, presente en el evento `result`. Es lo que
  /// permite continuar la conversación con `--resume`.
  final String? sessionId;

  /// Código de salida del proceso, en el evento `result`.
  final int? exitCode;

  /// Peticiones premium consumidas por el turno.
  final int? premiumRequests;

  /// Duración de las llamadas al modelo, en milisegundos.
  final int? apiDurationMs;

  /// Nombre de la herramienta ([CopilotEventKind.toolStart] / [toolEnd]).
  final String? toolName;

  /// Descripción legible del progreso de arranque.
  final String? detail;

  const CopilotEvent({
    required this.kind,
    this.text,
    this.model,
    this.sessionId,
    this.exitCode,
    this.premiumRequests,
    this.apiDurationMs,
    this.toolName,
    this.detail,
  });

  /// Convierte una línea JSONL en un evento normalizado.
  ///
  /// Devuelve `null` si la línea no es JSON válido: la CLI puede intercalar
  /// banners o avisos en texto plano, y no deben tumbar el stream.
  static CopilotEvent? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final type = decoded['type'] as String?;
    final data = decoded['data'];
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};

    switch (type) {
      case 'assistant.message_delta':
        final delta = map['deltaContent'];
        if (delta is! String || delta.isEmpty) return null;
        return CopilotEvent(kind: CopilotEventKind.delta, text: delta);

      case 'assistant.message':
        return CopilotEvent(
          kind: CopilotEventKind.message,
          text: map['content'] as String?,
          model: map['model'] as String?,
        );

      case 'assistant.turn_start':
        return CopilotEvent(
          kind: CopilotEventKind.turnStart,
          model: map['model'] as String?,
        );

      case 'session.tools_updated':
        return CopilotEvent(
          kind: CopilotEventKind.startup,
          model: map['model'] as String?,
          detail: 'Preparando herramientas',
        );

      case 'session.mcp_server_status_changed':
        final name = map['serverName'];
        return CopilotEvent(
          kind: CopilotEventKind.startup,
          detail: name is String ? 'Conectando $name' : 'Conectando servidores',
        );

      case 'session.mcp_servers_loaded':
        return CopilotEvent(
          kind: CopilotEventKind.startup,
          detail: 'Servidores listos',
        );

      case 'session.skills_loaded':
        return CopilotEvent(
          kind: CopilotEventKind.startup,
          detail: 'Cargando skills',
        );

      case 'session.custom_agents_updated':
        return CopilotEvent(
          kind: CopilotEventKind.startup,
          detail: 'Cargando agentes',
        );

      // El nombre exacto de los eventos de herramienta varía entre versiones,
      // así que se aceptan las formas conocidas.
      case 'assistant.tool_call':
      case 'tool.execution_start':
      case 'tool.start':
        return CopilotEvent(
          kind: CopilotEventKind.toolStart,
          toolName: (map['name'] ?? map['toolName']) as String?,
        );

      case 'tool.execution_end':
      case 'tool.end':
      case 'tool.result':
        return CopilotEvent(
          kind: CopilotEventKind.toolEnd,
          toolName: (map['name'] ?? map['toolName']) as String?,
        );

      case 'result':
        // `result` es plano: sessionId y usage cuelgan de la raíz.
        final usage = decoded['usage'];
        final usageMap = usage is Map<String, dynamic>
            ? usage
            : const <String, dynamic>{};
        return CopilotEvent(
          kind: CopilotEventKind.result,
          sessionId: decoded['sessionId'] as String?,
          exitCode: (decoded['exitCode'] as num?)?.toInt(),
          premiumRequests: (usageMap['premiumRequests'] as num?)?.toInt(),
          apiDurationMs: (usageMap['totalApiDurationMs'] as num?)?.toInt(),
        );

      default:
        return const CopilotEvent(kind: CopilotEventKind.unknown);
    }
  }
}
