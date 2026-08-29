class DatoInfo {
  final int? cdDato;
  final String? deDato;
  final String? tpDato;
  final int? nuLongitud;
  final int? nuDecimales;
  final int? cdTabla;
  final bool? inUso;
  final int? cdBusqueda;
  final bool? inConsultaSiniestro;
  final bool? inValidaPersona;
  final bool? inAsignacionAutomatica;
  final Map<String, dynamic> raw;

  const DatoInfo({
    this.cdDato,
    this.deDato,
    this.tpDato,
    this.nuLongitud,
    this.nuDecimales,
    this.cdTabla,
    this.inUso,
    this.cdBusqueda,
    this.inConsultaSiniestro,
    this.inValidaPersona,
    this.inAsignacionAutomatica,
    required this.raw,
  });

  bool get esTabla => cdTabla != null;

  factory DatoInfo.fromJson(Map<String, dynamic> json) => DatoInfo(
    cdDato: _n(json['cdDato']),
    deDato: json['deDato'] as String?,
    tpDato: json['tpDato'] as String?,
    nuLongitud: _n(json['nuLongitud']),
    nuDecimales: _n(json['nuDecimales']),
    cdTabla: _n(json['cdTabla']),
    inUso: _b(json['inUso']),
    cdBusqueda: _n(json['cdBusqueda']),
    inConsultaSiniestro: _b(json['inConsultaSiniestro']),
    inValidaPersona: _b(json['inValidaPersona']),
    inAsignacionAutomatica: _b(json['inAsignacionAutomatica']),
    raw: json,
  );

  static int? _n(dynamic v) => v == null ? null : (v as num).toInt();
  static bool? _b(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return null;
  }
}

class TablaDefinicion {
  final int? cdTabla;
  final String? deTabla;
  final bool? inComboConsulta;
  final String? nmPackageLlenado;
  final List<DatoColumna> columnas;
  final Map<String, dynamic> raw;

  const TablaDefinicion({
    this.cdTabla,
    this.deTabla,
    this.inComboConsulta,
    this.nmPackageLlenado,
    required this.columnas,
    required this.raw,
  });

  factory TablaDefinicion.fromJson(Map<String, dynamic> json) {
    final list = json['datos'] as List<dynamic>? ?? const <dynamic>[];
    return TablaDefinicion(
      cdTabla: _n(json['cdTabla']),
      deTabla: json['deTabla'] as String?,
      inComboConsulta: _b(json['inComboConsulta']),
      nmPackageLlenado: json['nmPackageLlenado'] as String?,
      columnas: list
          .whereType<Map<String, dynamic>>()
          .map(DatoColumna.fromJson)
          .toList(),
      raw: json,
    );
  }

  static int? _n(dynamic v) => v == null ? null : (v as num).toInt();
  static bool? _b(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return null;
  }
}

class DatoColumna {
  final int? numero;
  final int? cdDato;
  final String? deDato;
  final Map<String, dynamic> raw;

  const DatoColumna({this.numero, this.cdDato, this.deDato, required this.raw});

  factory DatoColumna.fromJson(Map<String, dynamic> json) => DatoColumna(
    numero: json['numero'] == null ? null : (json['numero'] as num).toInt(),
    cdDato: json['cdDato'] == null ? null : (json['cdDato'] as num).toInt(),
    deDato: json['deDato'] as String?,
    raw: json,
  );
}

class ValorTabla {
  final Map<String, dynamic> raw;
  const ValorTabla({required this.raw});
  factory ValorTabla.fromJson(Map<String, dynamic> json) =>
      ValorTabla(raw: json);
}
