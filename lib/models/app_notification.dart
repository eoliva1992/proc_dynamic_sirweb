import 'dart:convert';

enum AppNotificationKind { info, success, warning, error }

class AppNotification {
  final String id;
  final String? group;
  final String title;
  final String message;
  final AppNotificationKind kind;
  final String? source;
  final String? operationId;
  final double? percent;
  final DateTime timestamp;
  final DateTime? readAt;
  final Map<String, dynamic>? data;
  final bool read;

  AppNotification({
    required this.id,
    this.group,
    required this.title,
    required this.message,
    this.kind = AppNotificationKind.info,
    this.source,
    this.operationId,
    this.percent,
    required this.timestamp,
    this.readAt,
    this.data,
    this.read = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    AppNotificationKind parseKind(dynamic val) {
      if (val is int) {
        // Enums numéricos del backend: 1=Info, 2=Success, 3=Warning, 4=Error
        switch (val) {
          case 2:
            return AppNotificationKind.success;
          case 3:
            return AppNotificationKind.warning;
          case 4:
            return AppNotificationKind.error;
          case 1:
          default:
            return AppNotificationKind.info;
        }
      }
      final s = val?.toString().toLowerCase() ?? '';
      if (s.contains('success') || s.contains('éxito')) {
        return AppNotificationKind.success;
      }
      if (s.contains('warn') || s.contains('aviso')) {
        return AppNotificationKind.warning;
      }
      if (s.contains('err') || s.contains('fallo')) {
        return AppNotificationKind.error;
      }
      return AppNotificationKind.info;
    }

    DateTime? tryParseDate(dynamic val) {
      if (val is String && val.trim().isNotEmpty) {
        return DateTime.tryParse(val.trim());
      }
      return null;
    }

    DateTime parseTime(dynamic val) {
      final parsed = tryParseDate(val);
      if (parsed != null) return parsed;
      return DateTime.now();
    }

    // Procesar dataJson o data
    Map<String, dynamic>? dataMap;
    if (json['data'] is Map) {
      dataMap = Map<String, dynamic>.from(json['data'] as Map);
    } else if (json['dataJson'] != null) {
      final raw = json['dataJson'];
      if (raw is Map) {
        dataMap = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            dataMap = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }

    final message =
        json['message']?.toString() ?? json['mensaje']?.toString() ?? '';
    final source =
        json['source']?.toString() ?? json['origen']?.toString() ?? '';
    final title =
        json['title']?.toString() ??
        json['titulo']?.toString() ??
        (source.isNotEmpty ? source : 'Notificación');

    final readAt = tryParseDate(json['readAt'] ?? json['fechaLectura']);
    final isRead = json['read'] == true || readAt != null;

    double? parsePercent(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    return AppNotification(
      id:
          json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      group: json['group']?.toString() ?? json['grupo']?.toString(),
      title: title,
      message: message,
      kind: parseKind(json['kind'] ?? json['type'] ?? json['tipo']),
      source: source,
      operationId: json['operationId']?.toString(),
      percent: parsePercent(json['percent']),
      timestamp: parseTime(
        json['createdAt'] ?? json['timestamp'] ?? json['fecha'],
      ),
      readAt: readAt,
      data: dataMap,
      read: isRead,
    );
  }

  AppNotification copyWith({
    String? id,
    String? group,
    String? title,
    String? message,
    AppNotificationKind? kind,
    String? source,
    String? operationId,
    double? percent,
    DateTime? timestamp,
    DateTime? readAt,
    Map<String, dynamic>? data,
    bool? read,
  }) {
    return AppNotification(
      id: id ?? this.id,
      group: group ?? this.group,
      title: title ?? this.title,
      message: message ?? this.message,
      kind: kind ?? this.kind,
      source: source ?? this.source,
      operationId: operationId ?? this.operationId,
      percent: percent ?? this.percent,
      timestamp: timestamp ?? this.timestamp,
      readAt: readAt ?? this.readAt,
      data: data ?? this.data,
      read: read ?? this.read,
    );
  }
}

class NotificationPageResponse {
  final List<AppNotification> items;
  final int pagina;
  final int top;
  final bool tieneSiguiente;
  final bool tienePrevio;

  const NotificationPageResponse({
    required this.items,
    required this.pagina,
    required this.top,
    required this.tieneSiguiente,
    required this.tienePrevio,
  });

  factory NotificationPageResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();

    return NotificationPageResponse(
      items: items,
      pagina: json['pagina'] is int ? json['pagina'] as int : 1,
      top: json['top'] is int ? json['top'] as int : items.length,
      tieneSiguiente: json['tieneSiguiente'] == true,
      tienePrevio: json['tienePrevio'] == true,
    );
  }
}
