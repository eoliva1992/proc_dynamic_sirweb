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
  final List<DatoProducto> productos;
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
    this.productos = const [],
    required this.raw,
  });

  bool get esTabla => cdTabla != null;

  factory DatoInfo.fromJson(Map<String, dynamic> json) {
    // Si la respuesta viene con formato { "dato": { ... }, "productos": [ ... ] }
    final Map<String, dynamic> datoMap;
    final List<dynamic> prodsList;

    if (json.containsKey('dato') && json['dato'] is Map<String, dynamic>) {
      datoMap = json['dato'] as Map<String, dynamic>;
      prodsList = json['productos'] as List<dynamic>? ?? const [];
    } else {
      datoMap = json;
      prodsList = json['productos'] as List<dynamic>? ?? const [];
    }

    final productos = prodsList
        .whereType<Map<String, dynamic>>()
        .map(DatoProducto.fromJson)
        .toList();

    return DatoInfo(
      cdDato: _n(datoMap['cdDato']),
      deDato: datoMap['deDato'] as String?,
      tpDato: datoMap['tpDato'] as String?,
      nuLongitud: _n(datoMap['nuLongitud']),
      nuDecimales: _n(datoMap['nuDecimales']),
      cdTabla: _n(datoMap['cdTabla']),
      inUso: _b(datoMap['inUso']),
      cdBusqueda: _n(datoMap['cdBusqueda']),
      inConsultaSiniestro: _b(datoMap['inConsultaSiniestro']),
      inValidaPersona: _b(datoMap['inValidaPersona']),
      inAsignacionAutomatica: _b(datoMap['inAsignacionAutomatica']),
      productos: productos,
      raw: datoMap,
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

class DatoProducto {
  final int? version;
  final int? cdProducto;
  final String? deProducto;
  final int? nuBienAsegurado;
  final int? cdDato;
  final int? cdGrupo;
  final int? inDatoRequerido;
  final int? inLugarUsoDato;
  final String? vaDefectoDato;
  final int? inIndexar;
  final int? inActivo;
  final String? cdProcedimientoAntes;
  final String? cdProcedimientoDespues;
  final int? nuConsecutivo;
  final String? cdJavascriptDespues;
  final int? inMatrizCertificado;
  final int? inMostrarSiniestro;
  final int? inEndoso;
  final int? inMostrarCertificado;
  final int? inArrastreValor;
  final int? inEjecRenovacionProcAnt;
  final int? inEjecRenovacionProcDesp;
  final int? inNoMostrarConsultaOtros;
  final int? inBusquedaSiniestro;
  final int? inNoMostrarWebExterna;
  final String? vaDefectoDatoWebExterna;
  final int? inNoMostrarWebMediador;
  final String? vaDefectoDatoWebMediador;
  final int? inDataWarehouse;
  final int? inConsultaTotalizada;
  final int? inInvisibleDefecto;
  final int? inMostrarMercancia;
  final int? cdDatoPadre;
  final int? inEndosoMultiple;
  final String? nmPackageAjax;
  final int? inRecargarDatos;
  final int? inAplicarPoCoaseguro;
  final int? inNoMostrarWebDelegado;
  final String? vaDefectoDatoWebDelegado;
  final int? inNoMostrarEndosoWebMedi;
  final int? inNoMostrarEndosoWebExte;
  final int? inNoMostrarEndosoWebDele;
  final Map<String, dynamic> raw;

  const DatoProducto({
    this.version,
    this.cdProducto,
    this.deProducto,
    this.nuBienAsegurado,
    this.cdDato,
    this.cdGrupo,
    this.inDatoRequerido,
    this.inLugarUsoDato,
    this.vaDefectoDato,
    this.inIndexar,
    this.inActivo,
    this.cdProcedimientoAntes,
    this.cdProcedimientoDespues,
    this.nuConsecutivo,
    this.cdJavascriptDespues,
    this.inMatrizCertificado,
    this.inMostrarSiniestro,
    this.inEndoso,
    this.inMostrarCertificado,
    this.inArrastreValor,
    this.inEjecRenovacionProcAnt,
    this.inEjecRenovacionProcDesp,
    this.inNoMostrarConsultaOtros,
    this.inBusquedaSiniestro,
    this.inNoMostrarWebExterna,
    this.vaDefectoDatoWebExterna,
    this.inNoMostrarWebMediador,
    this.vaDefectoDatoWebMediador,
    this.inDataWarehouse,
    this.inConsultaTotalizada,
    this.inInvisibleDefecto,
    this.inMostrarMercancia,
    this.cdDatoPadre,
    this.inEndosoMultiple,
    this.nmPackageAjax,
    this.inRecargarDatos,
    this.inAplicarPoCoaseguro,
    this.inNoMostrarWebDelegado,
    this.vaDefectoDatoWebDelegado,
    this.inNoMostrarEndosoWebMedi,
    this.inNoMostrarEndosoWebExte,
    this.inNoMostrarEndosoWebDele,
    required this.raw,
  });

  factory DatoProducto.fromJson(Map<String, dynamic> json) => DatoProducto(
    version: _n(json['version']),
    cdProducto: _n(json['cdProducto']),
    deProducto: json['deProducto'] as String?,
    nuBienAsegurado: _n(json['nuBienAsegurado']),
    cdDato: _n(json['cdDato']),
    cdGrupo: _n(json['cdGrupo']),
    inDatoRequerido: _n(json['inDatoRequerido']),
    inLugarUsoDato: _n(json['inLugarUsoDato']),
    vaDefectoDato: json['vaDefectoDato']?.toString(),
    inIndexar: _n(json['inIndexar']),
    inActivo: _n(json['inActivo']),
    cdProcedimientoAntes: json['cdProcedimientoAntes'] as String?,
    cdProcedimientoDespues: json['cdProcedimientoDespues'] as String?,
    nuConsecutivo: _n(json['nuConsecutivo']),
    cdJavascriptDespues: json['cdJavascriptDespues'] as String?,
    inMatrizCertificado: _n(json['inMatrizCertificado']),
    inMostrarSiniestro: _n(json['inMostrarSiniestro']),
    inEndoso: _n(json['inEndoso']),
    inMostrarCertificado: _n(json['inMostrarCertificado']),
    inArrastreValor: _n(json['inArrastreValor']),
    inEjecRenovacionProcAnt: _n(json['inEjecRenovacionProcAnt']),
    inEjecRenovacionProcDesp: _n(json['inEjecRenovacionProcDesp']),
    inNoMostrarConsultaOtros: _n(json['inNoMostrarConsultaOtros']),
    inBusquedaSiniestro: _n(json['inBusquedaSiniestro']),
    inNoMostrarWebExterna: _n(json['inNoMostrarWebExterna']),
    vaDefectoDatoWebExterna: json['vaDefectoDatoWebExterna']?.toString(),
    inNoMostrarWebMediador: _n(json['inNoMostrarWebMediador']),
    vaDefectoDatoWebMediador: json['vaDefectoDatoWebMediador']?.toString(),
    inDataWarehouse: _n(json['inDataWarehouse']),
    inConsultaTotalizada: _n(json['inConsultaTotalizada']),
    inInvisibleDefecto: _n(json['inInvisibleDefecto']),
    inMostrarMercancia: _n(json['inMostrarMercancia']),
    cdDatoPadre: _n(json['cdDatoPadre']),
    inEndosoMultiple: _n(json['inEndosoMultiple']),
    nmPackageAjax: json['nmPackageAjax'] as String?,
    inRecargarDatos: _n(json['inRecargarDatos']),
    inAplicarPoCoaseguro: _n(json['inAplicarPoCoaseguro']),
    inNoMostrarWebDelegado: _n(json['inNoMostrarWebDelegado']),
    vaDefectoDatoWebDelegado: json['vaDefectoDatoWebDelegado']?.toString(),
    inNoMostrarEndosoWebMedi: _n(json['inNoMostrarEndosoWebMedi']),
    inNoMostrarEndosoWebExte: _n(json['inNoMostrarEndosoWebExte']),
    inNoMostrarEndosoWebDele: _n(json['inNoMostrarEndosoWebDele']),
    raw: json,
  );

  static int? _n(dynamic v) => v == null ? null : (v as num).toInt();
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
