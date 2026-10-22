import 'dart:convert';

/// Estado de una traza HTTP.
enum SqlHttpTraceStatus { running, success, error, cancelled }

/// Representa una entrada de monitoreo y auditoría HTTP en el ejecutor SQL.
///
/// Registra el ciclo completo de vida de la petición: URL, método, cabeceras,
/// payload/body enviado en formato JSON, código de respuesta HTTP devuelto
/// por el backend SirWeb, duración en milisegundos y cuerpo crudo devuelto.
class SqlHttpTraceEntry {
  SqlHttpTraceEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    required this.endpoint,
    this.requestHeaders = const {},
    this.requestBody,
    this.statusCode,
    this.durationMs,
    this.responseBody,
    this.status = SqlHttpTraceStatus.running,
    this.error,
  });

  final int id;
  final DateTime timestamp;
  final String method;
  final String url;
  final String endpoint;
  final Map<String, String> requestHeaders;
  final String? requestBody;

  int? statusCode;
  int? durationMs;
  String? responseBody;
  SqlHttpTraceStatus status;
  String? error;

  /// Devuelve el cuerpo de la petición formateado con indentación si es JSON válido.
  String get prettyRequestBody {
    final body = requestBody;
    if (body == null || body.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }

  /// Devuelve el cuerpo de la respuesta formateado con indentación si es JSON válido.
  String get prettyResponseBody {
    final body = responseBody;
    if (body == null || body.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }

  /// Genera un comando cURL equivalente para depuración rápida en terminal o Postman.
  String toCurlCommand() {
    final buffer = StringBuffer('curl -X $method "$url"');
    for (final entry in requestHeaders.entries) {
      buffer.write(' -H "${entry.key}: ${entry.value}"');
    }
    if (requestBody != null && requestBody!.isNotEmpty) {
      final escaped = requestBody!.replaceAll('"', '\\"');
      buffer.write(' -d "$escaped"');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'method': method,
    'url': url,
    'endpoint': endpoint,
    'requestHeaders': requestHeaders,
    'requestBody': requestBody,
    'statusCode': statusCode,
    'durationMs': durationMs,
    'responseBody': responseBody,
    'status': status.name,
    'error': error,
  };

  factory SqlHttpTraceEntry.fromJson(Map<String, dynamic> json) {
    return SqlHttpTraceEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      method: json['method']?.toString() ?? 'POST',
      url: json['url']?.toString() ?? '',
      endpoint: json['endpoint']?.toString() ?? '',
      requestHeaders:
          (json['requestHeaders'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v?.toString() ?? ''),
          ) ??
          const {},
      requestBody: json['requestBody']?.toString(),
      statusCode: (json['statusCode'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      responseBody: json['responseBody']?.toString(),
      status: SqlHttpTraceStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SqlHttpTraceStatus.success,
      ),
      error: json['error']?.toString(),
    );
  }
}
