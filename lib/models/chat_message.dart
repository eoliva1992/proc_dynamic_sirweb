/// Rol de un mensaje dentro de la conversación con Copilot.
enum ChatRole { user, assistant, system }

/// Una herramienta que el agente invocó durante el turno.
class ChatToolCall {
  final String name;
  bool finished;

  ChatToolCall(this.name, {this.finished = false});
}

/// Un mensaje del chat con Copilot.
///
/// El contenido es mutable mientras la respuesta llega en streaming: el panel
/// crea el mensaje vacío con [isStreaming] en `true` y lo va completando con
/// [appendChunk] a medida que la CLI emite eventos `assistant.message_delta`.
class ChatMessage {
  final String id;
  final ChatRole role;
  final DateTime timestamp;
  String content;
  bool isStreaming;
  bool isError;

  /// Modelo que generó la respuesta (`claude-sonnet-5`, `gpt-5`…).
  String? model;

  /// Fase de arranque de la CLI, mientras aún no llega texto.
  String? statusDetail;

  /// Herramientas invocadas durante el turno.
  final List<ChatToolCall> toolCalls;

  /// Peticiones premium consumidas y duración de la llamada al modelo.
  int? premiumRequests;
  int? apiDurationMs;

  /// Contexto que se envió con la pregunta (sello del mensaje del usuario).
  String? contextLabel;

  /// Modo en que se generó la respuesta (plan, gent, sk).
  ///
  /// Se guarda en el mensaje y no en el panel porque una conversación puede
  /// alternar de modo: la barra «Continuar desde el plan» necesita saber si
  /// **esa** respuesta concreta era un plan.
  String? mode;

  /// El código de esta respuesta ya se escribió en el documento.
  ///
  /// No se persiste: al reabrir el hilo el editor puede tener otro
  /// contenido, y afirmar que sigue aplicado sería mentir.
  bool applied = false;

  ChatMessage({
    required this.role,
    required this.content,
    String? id,
    DateTime? timestamp,
    this.isStreaming = false,
    this.isError = false,
    this.model,
    this.statusDetail,
    this.premiumRequests,
    this.apiDurationMs,
    this.contextLabel,
    this.mode,
    List<ChatToolCall>? toolCalls,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
       timestamp = timestamp ?? DateTime.now(),
       toolCalls = toolCalls ?? [];

  factory ChatMessage.user(String content, {String? contextLabel}) =>
      ChatMessage(
        role: ChatRole.user,
        content: content,
        contextLabel: contextLabel,
      );

  factory ChatMessage.assistant(
    String content, {
    bool isStreaming = false,
    String? mode,
  }) => ChatMessage(
    role: ChatRole.assistant,
    content: content,
    isStreaming: isStreaming,
    mode: mode,
  );

  factory ChatMessage.error(String content) =>
      ChatMessage(role: ChatRole.assistant, content: content, isError: true);

  void appendChunk(String chunk) => content += chunk;

  bool get isUser => role == ChatRole.user;

  /// `true` mientras se espera la primera palabra de la respuesta.
  bool get isPending => isStreaming && content.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    if (isError) 'isError': true,
    if (model != null) 'model': model,
    if (contextLabel != null) 'contextLabel': contextLabel,
    if (mode != null) 'mode': mode,
    if (premiumRequests != null) 'premiumRequests': premiumRequests,
    if (apiDurationMs != null) 'apiDurationMs': apiDurationMs,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String?,
    role: ChatRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => ChatRole.assistant,
    ),
    content: (json['content'] ?? '') as String,
    timestamp:
        DateTime.tryParse((json['timestamp'] ?? '') as String) ??
        DateTime.now(),
    isError: json['isError'] == true,
    model: json['model'] as String?,
    contextLabel: json['contextLabel'] as String?,
    mode: json['mode'] as String?,
    premiumRequests: (json['premiumRequests'] as num?)?.toInt(),
    apiDurationMs: (json['apiDurationMs'] as num?)?.toInt(),
  );
}

// ── Markdown ─────────────────────────────────────────────────────────────────

/// Tipo de bloque markdown reconocido en una respuesta.
enum MdBlockKind { paragraph, code, heading, bullet, numbered, quote, rule }

/// Un bloque de la respuesta ya clasificado para renderizar.
class MdBlock {
  final MdBlockKind kind;
  final String text;

  /// Lenguaje del bloque de código (`sql`, `dart`…), si viene indicado.
  final String? language;

  /// Nivel del encabezado (1-6) o de anidamiento de la lista.
  final int level;

  /// Marcador de la lista numerada (`1.`, `2.`…).
  final String? marker;

  const MdBlock({
    required this.kind,
    required this.text,
    this.language,
    this.level = 0,
    this.marker,
  });

  bool get isCode => kind == MdBlockKind.code;
}

/// Fragmento en línea con estilo.
enum MdSpanStyle { normal, bold, italic, code, link }

class MdSpan {
  final String text;
  final MdSpanStyle style;

  /// Destino, solo para [MdSpanStyle.link].
  final String? href;

  const MdSpan(this.text, this.style, {this.href});
}

/// Divide una respuesta markdown en bloques renderizables.
///
/// Soporta fences de código (tolerando el cierre ausente durante el
/// streaming), encabezados `#`, listas con viñeta y numeradas, citas `>` y
/// reglas horizontales. El resto se agrupa en párrafos.
List<MdBlock> parseMarkdownBlocks(String content) {
  final blocks = <MdBlock>[];
  final lines = content.replaceAll('\r\n', '\n').split('\n');

  final paragraph = <String>[];
  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join('\n').trim();
    if (text.isNotEmpty) {
      blocks.add(MdBlock(kind: MdBlockKind.paragraph, text: text));
    }
    paragraph.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final fence = RegExp(r'^\s*```([\w+-]*)\s*$').firstMatch(line);

    if (fence != null) {
      flushParagraph();
      final lang = fence.group(1)?.trim();
      final buffer = <String>[];
      i++;
      // Si el fence de cierre no ha llegado todavía (streaming), se consume
      // hasta el final y el bloque se pinta igualmente.
      while (i < lines.length && !RegExp(r'^\s*```\s*$').hasMatch(lines[i])) {
        buffer.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // salta el cierre
      blocks.add(
        MdBlock(
          kind: MdBlockKind.code,
          text: buffer.join('\n').trimRight(),
          language: (lang == null || lang.isEmpty) ? null : lang,
        ),
      );
      continue;
    }

    if (RegExp(r'^\s*(---+|\*\*\*+|___+)\s*$').hasMatch(line)) {
      flushParagraph();
      blocks.add(const MdBlock(kind: MdBlockKind.rule, text: ''));
      i++;
      continue;
    }

    final heading = RegExp(r'^\s*(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(
        MdBlock(
          kind: MdBlockKind.heading,
          text: heading.group(2)!.trim(),
          level: heading.group(1)!.length,
        ),
      );
      i++;
      continue;
    }

    final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(
        MdBlock(
          kind: MdBlockKind.bullet,
          text: bullet.group(2)!.trim(),
          level: (bullet.group(1)!.length / 2).floor(),
        ),
      );
      i++;
      continue;
    }

    final numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(line);
    if (numbered != null) {
      flushParagraph();
      blocks.add(
        MdBlock(
          kind: MdBlockKind.numbered,
          text: numbered.group(3)!.trim(),
          level: (numbered.group(1)!.length / 2).floor(),
          marker: '${numbered.group(2)}.',
        ),
      );
      i++;
      continue;
    }

    final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
    if (quote != null) {
      flushParagraph();
      blocks.add(MdBlock(kind: MdBlockKind.quote, text: quote.group(1)!));
      i++;
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
    } else {
      paragraph.add(line);
    }
    i++;
  }

  flushParagraph();
  return blocks;
}

/// Divide una línea en fragmentos con estilo: `**negrita**`, `*cursiva*`,
/// `` `código` `` y `[texto](url)`.
List<MdSpan> parseInlineSpans(String text) {
  final spans = <MdSpan>[];
  final pattern = RegExp(
    r'(\*\*[^*]+\*\*)'
    r'|(`[^`]+`)'
    r'|(\[[^\]]+\]\([^)]+\))'
    r'|(\*[^*\n]+\*)'
    r'|(_[^_\n]+_)',
  );

  var index = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > index) {
      spans.add(MdSpan(text.substring(index, m.start), MdSpanStyle.normal));
    }
    final token = m.group(0)!;
    if (token.startsWith('**')) {
      spans.add(MdSpan(token.substring(2, token.length - 2), MdSpanStyle.bold));
    } else if (token.startsWith('`')) {
      spans.add(MdSpan(token.substring(1, token.length - 1), MdSpanStyle.code));
    } else if (token.startsWith('[')) {
      final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token)!;
      spans.add(MdSpan(link.group(1)!, MdSpanStyle.link, href: link.group(2)));
    } else {
      spans.add(
        MdSpan(token.substring(1, token.length - 1), MdSpanStyle.italic),
      );
    }
    index = m.end;
  }
  if (index < text.length) {
    spans.add(MdSpan(text.substring(index), MdSpanStyle.normal));
  }
  return spans.isEmpty ? [MdSpan(text, MdSpanStyle.normal)] : spans;
}

// ── Slash commands ───────────────────────────────────────────────────────────

/// Comando rápido al estilo de los *slash commands* de Copilot Chat en VS Code.
class ChatSlashCommand {
  /// Nombre sin la barra, p. ej. `explicar`.
  final String name;
  final String description;

  /// Instrucción que se antepone a la pregunta del usuario.
  final String template;

  // No hay bandera `requiresCode`: el documento abierto se adjunta siempre,
  // así que todos los comandos cuentan con él.

  const ChatSlashCommand({
    required this.name,
    required this.description,
    required this.template,
  });
}

/// Comandos disponibles, equivalentes a `/explain`, `/fix`, `/tests`… de VS Code
/// pero adaptados al dominio PL/SQL de Sirweb.
const kChatSlashCommands = <ChatSlashCommand>[
  ChatSlashCommand(
    name: 'explicar',
    description: 'Explica qué hace el código',
    template:
        'Explica de forma clara y estructurada qué hace el siguiente código '
        'PL/SQL, incluyendo su propósito de negocio.',
  ),
  ChatSlashCommand(
    name: 'corregir',
    description: 'Propone una corrección de los errores',
    template:
        'Detecta y corrige los errores del siguiente código PL/SQL. Devuelve '
        'el bloque corregido y explica brevemente cada cambio.',
  ),
  ChatSlashCommand(
    name: 'optimizar',
    description: 'Sugiere mejoras de rendimiento',
    template:
        'Analiza el rendimiento del siguiente código PL/SQL y propone '
        'optimizaciones concretas (índices, cursores, SQL masivo).',
  ),
  ChatSlashCommand(
    name: 'documentar',
    description: 'Genera comentarios y documentación',
    template:
        'Documenta el siguiente código PL/SQL con comentarios claros en '
        'español, respetando el estilo existente.',
  ),
  ChatSlashCommand(
    name: 'revisar',
    description: 'Revisión de código en busca de riesgos',
    template:
        'Haz una revisión del siguiente código PL/SQL: errores potenciales, '
        'manejo de excepciones, transacciones y buenas prácticas Oracle.',
  ),
  ChatSlashCommand(
    name: 'tests',
    description: 'Sugiere casos de prueba',
    template:
        'Propón casos de prueba para el siguiente código PL/SQL, incluyendo '
        'valores límite y escenarios de error.',
  ),
];

/// Si [text] empieza por `/comando`, devuelve el comando y el resto del texto.
({ChatSlashCommand? command, String rest}) parseSlashCommand(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('/')) return (command: null, rest: text);
  final match = RegExp(r'^/(\w+)\s*([\s\S]*)$').firstMatch(trimmed);
  if (match == null) return (command: null, rest: text);
  final name = match.group(1)!.toLowerCase();
  for (final c in kChatSlashCommands) {
    if (c.name == name) return (command: c, rest: match.group(2) ?? '');
  }
  return (command: null, rest: text);
}
