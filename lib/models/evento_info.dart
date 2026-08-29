class EventoDato {
  final int numero;
  final int cdDato;
  final String deDato;
  final Map<String, dynamic> raw;

  const EventoDato({
    required this.numero,
    required this.cdDato,
    required this.deDato,
    required this.raw,
  });

  factory EventoDato.fromJson(Map<String, dynamic> json) => EventoDato(
    numero: (json['numero'] as num?)?.toInt() ?? 0,
    cdDato: (json['cdDato'] as num?)?.toInt() ?? 0,
    deDato: json['deDato']?.toString() ?? '',
    raw: json,
  );
}

class EventoValor {
  final int? indice;
  final String? valor;
  final String? descripcion;
  final Map<String, dynamic> raw;

  EventoValor({this.indice, this.valor, this.descripcion, required this.raw});

  factory EventoValor.fromJson(Map<String, dynamic> json) {
    return EventoValor(
      indice:
          json['indice'] as int? ??
          json['cdIndice'] as int? ??
          json['index'] as int?,
      valor:
          json['valor']?.toString() ??
          json['cdValor']?.toString() ??
          json['value']?.toString(),
      descripcion:
          json['descripcion']?.toString() ??
          json['deValor']?.toString() ??
          json['description']?.toString(),
      raw: json,
    );
  }
}

class EventoInfo {
  final String cdEvento;
  final String? deEvento;
  final String? tipo;
  final List<EventoDato> datos;
  final bool? inUsoUltDato;
  final bool? inUsoTasa;
  final int? cdComponente;
  final String? deVaComponente;
  final String? deVaMinima;
  final String? deVaMaxima;
  final bool? inManejaMinMax;
  final bool? inManejaAdicional;
  final String? deVaAdicional;
  final bool? inMinimoRequerido;
  final bool? inMaximoRequerido;
  final bool? inAplicaTasaCambio;
  final List<EventoValor> valores;

  EventoInfo({
    required this.cdEvento,
    this.deEvento,
    this.tipo,
    this.datos = const [],
    this.inUsoUltDato,
    this.inUsoTasa,
    this.cdComponente,
    this.deVaComponente,
    this.deVaMinima,
    this.deVaMaxima,
    this.inManejaMinMax,
    this.inManejaAdicional,
    this.deVaAdicional,
    this.inMinimoRequerido,
    this.inMaximoRequerido,
    this.inAplicaTasaCambio,
    required this.valores,
  });

  static bool? _parseBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) {
      final s = v.trim().toUpperCase();
      return s == '1' || s == 'S' || s == 'TRUE';
    }
    return null;
  }

  /// Construye EventoInfo a partir de las 2 respuestas separadas:
  /// [infoResult] = respuesta de `info_evento` (encabezado/definición)
  /// [valoresResult] = respuesta de `valores_evento` (lista EVENTOVALOR)
  factory EventoInfo.fromSeparateResponses(
    String cdEvento,
    Map<String, dynamic> infoResult,
    Map<String, dynamic> valoresResult,
  ) {
    final infoData = infoResult['data'];
    final body = infoData is Map<String, dynamic>
        ? infoData
        : <String, dynamic>{};

    final valoresData = valoresResult['data'];
    final rawValores = valoresData is List<dynamic>
        ? valoresData
        : (valoresData is Map<String, dynamic>
              ? (valoresData['items'] as List<dynamic>? ??
                    valoresData['valores'] as List<dynamic>? ??
                    [])
              : <dynamic>[]);

    return EventoInfo(
      cdEvento: cdEvento,
      deEvento:
          body['deEvento']?.toString() ??
          body['descripcion']?.toString() ??
          body['description']?.toString(),
      tipo: body['tipo']?.toString() ?? body['type']?.toString(),
      datos: (body['datos'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EventoDato.fromJson)
          .toList(),
      inUsoUltDato: _parseBool(body['inUsoUltDato']),
      inUsoTasa: _parseBool(body['inUsoTasa']),
      cdComponente: (body['cdComponente'] as num?)?.toInt(),
      deVaComponente: body['deVaComponente']?.toString(),
      deVaMinima: body['deVaMinima']?.toString(),
      deVaMaxima: body['deVaMaxima']?.toString(),
      inManejaMinMax: _parseBool(body['inManejaMinMax']),
      inManejaAdicional: _parseBool(body['inManejaAdicional']),
      deVaAdicional: body['deVaAdicional']?.toString(),
      inMinimoRequerido: _parseBool(body['inMinimoRequerido']),
      inMaximoRequerido: _parseBool(body['inMaximoRequerido']),
      inAplicaTasaCambio: _parseBool(body['inAplicaTasaCambio']),
      valores: rawValores
          .whereType<Map<String, dynamic>>()
          .map(EventoValor.fromJson)
          .toList(),
    );
  }
}
