import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_message.dart';

/// Una conversación completa, equivalente a un *chat* de la barra lateral de
/// VS Code.
///
/// [sessionId] es el UUID que se pasa a la CLI (`--session-id` la primera vez,
/// `--resume` después). Gracias a él la CLI conserva el contexto en su propio
/// almacén y no hace falta reenviar el historial en cada pregunta.
class ChatConversation {
  final String id;

  /// UUID de la sesión de la CLI. `null` hasta que se envía el primer turno.
  String? sessionId;

  /// `true` cuando la CLI ya confirmó la sesión con un evento `result`.
  ///
  /// Solo entonces se puede usar `--resume`: lanzarlo contra un identificador
  /// que la CLI nunca llegó a registrar (porque el primer turno falló) haría
  /// fallar la invocación.
  bool sessionStarted;

  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;

  ChatConversation({
    required this.id,
    this.sessionId,
    this.sessionStarted = false,
    this.title = 'Nueva conversación',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       messages = messages ?? [];

  factory ChatConversation.nueva() =>
      ChatConversation(id: 'c${DateTime.now().microsecondsSinceEpoch}');

  bool get isEmpty => messages.isEmpty;

  /// Solo se puede reanudar cuando la CLI ya confirmó el identificador.
  bool get canResume => sessionStarted && sessionId != null;

  /// Título derivado de la primera pregunta, como hace VS Code.
  void autoTitle() {
    if (title != 'Nueva conversación') return;
    final first = messages.where((m) => m.isUser).firstOrNull;
    if (first == null) return;
    final clean = first.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    title = clean.length <= 42 ? clean : '${clean.substring(0, 42)}…';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'sessionStarted': sessionStarted,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: (json['id'] ?? '') as String,
        sessionId: json['sessionId'] as String?,
        sessionStarted: json['sessionStarted'] == true,
        title: (json['title'] ?? 'Conversación') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
        updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String),
        messages: ((json['messages'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList(),
      );
}

/// Persistencia de las conversaciones en `SharedPreferences`.
///
/// Se guardan las [maxConversations] más recientes; el resto se descarta para
/// no engordar las preferencias sin límite.
class ChatStore {
  ChatStore._();

  static final ChatStore instance = ChatStore._();

  static const _kPref = 'copilot_chat_conversations';
  static const maxConversations = 25;

  Future<List<ChatConversation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPref);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatConversation.fromJson)
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (_) {
      // Formato antiguo o corrupto: se empieza de cero en vez de fallar.
      return [];
    }
  }

  Future<void> save(List<ChatConversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final keep = conversations.where((c) => c.messages.isNotEmpty).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final trimmed = keep.take(maxConversations).toList();
    await prefs.setString(
      _kPref,
      jsonEncode(trimmed.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPref);
  }
}
