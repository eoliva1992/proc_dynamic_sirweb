/// Modelos para los endpoints de ejecución de reglas de negocio:
///
/// * `POST /tools/procedimiento-dinamico/{cdProcedimiento}/ejecutar`
///   ejecuta el texto guardado (se manda sólo el nombre en la URL);
/// * `POST /tools/procedimiento-dinamico/ejecutar-borrador`
///   ejecuta el `deTexto` que el usuario tiene en el editor, sin guardarlo.
///
/// Request (`/ejecutar`; el borrador agrega `deTexto` e `inConfiguracion`):
/// ```json
/// {
///   "cdEntidad": 1, "nuCotizacion": null, "nuItem": null, "cdArea": null,
///   "nuPoliza": null, "nuCertificado": null, "nuEndoso": null,
///   "nuSiniestro": null, "nuMovimiento": null, "nuInspeccion": null,
///   "inAccion": null, "vaDato": null, "stringDatos": null,
///   "stringMatriz": null, "camposAdicionales": null, "tipoContexto": null,
///   "ambiente": null, "timeoutSegundos": null
/// }
/// ```
///
/// Response: `{ success, message, error, data: { ...EjecucionResultado } }`
///
/// ```json
/// {
///   "ambiente": "Desa", "cdProcedimiento": "DR_TEST", "borrador": true,
///   "inConfiguracion": "D", "stProcedimiento": "1", "orquestador": "…",
///   "contexto": {
///     "tipo": "COTIZACION", "record": "r_cotizacion",
///     "camposDesdeBd": { "CD_PRODUCTO": "10" },
///     "camposSobreescritos": ["CD_AREA"], "camposSinResolver": ["NU_ENDOSO"]
///   },
///   "salidas": { "VA_RESULTADO": "OK" },
///   "variablesDinamicasUsadas": { "#FECHA#": "06/09/2026" },
///   "traza": ["…"], "errorOracle": null, "duracionMs": 42,
///   "rollback": true, "commitDetectado": false
/// }
/// ```
library;

/// Parámetros de contexto con los que se ejecuta la regla de negocio.
class EjecucionRequest {
  final int? cdEntidad;
  final int? nuCotizacion;
  final int? nuItem;
  final int? cdArea;
  final int? nuPoliza;
  final int? nuCertificado;
  final int? nuEndoso;
  final int? nuSiniestro;
  final int? nuMovimiento;
  final int? nuInspeccion;
  final String? inAccion;
  final String? vaDato;
  final String? stringDatos;
  final String? stringMatriz;

  /// Overrides puntuales del record de contexto (`CAMPO` → valor).
  final Map<String, dynamic>? camposAdicionales;
  final String? tipoContexto;
  final String? ambiente;
  final int? timeoutSegundos;

  const EjecucionRequest({
    this.cdEntidad = 1,
    this.nuCotizacion,
    this.nuItem,
    this.cdArea,
    this.nuPoliza,
    this.nuCertificado,
    this.nuEndoso,
    this.nuSiniestro,
    this.nuMovimiento,
    this.nuInspeccion,
    this.inAccion,
    this.vaDato,
    this.stringDatos,
    this.stringMatriz,
    this.camposAdicionales,
    this.tipoContexto,
    this.ambiente,
    this.timeoutSegundos,
  });

  /// El backend espera el contrato completo: los `null` se envían explícitos.
  Map<String, dynamic> toJson() => {
    'cdEntidad': cdEntidad,
    'nuCotizacion': nuCotizacion,
    'nuItem': nuItem,
    'cdArea': cdArea,
    'nuPoliza': nuPoliza,
    'nuCertificado': nuCertificado,
    'nuEndoso': nuEndoso,
    'nuSiniestro': nuSiniestro,
    'nuMovimiento': nuMovimiento,
    'nuInspeccion': nuInspeccion,
    'inAccion': inAccion,
    'vaDato': vaDato,
    'stringDatos': stringDatos,
    'stringMatriz': stringMatriz,
    'camposAdicionales': camposAdicionales,
    'tipoContexto': tipoContexto,
    'ambiente': ambiente,
    'timeoutSegundos': timeoutSegundos,
  };

  /// Contrato del endpoint `POST /tools/procedimiento-dinamico/ejecutar-borrador`.
  ///
  /// Es el mismo contexto que [toJson] más el código que el usuario tiene en
  /// el editor ([deTexto]) y su categoría ([inConfiguracion]): así se prueba
  /// lo que está escrito sin necesidad de guardarlo antes.
  Map<String, dynamic> toBorradorJson({
    required String deTexto,
    String? inConfiguracion,
  }) => {
    'deTexto': deTexto,
    'inConfiguracion': inConfiguracion ?? '',
    ...toJson(),
  };
}

/// Detalle del record de contexto que armó el orquestador.
class ContextoEjecucion {
  final String? tipo;
  final String? record;

  /// Campos resueltos leyendo la base: `CAMPO` → valor recuperado.
  final Map<String, dynamic> camposDesdeBd;
  final List<String> camposSobreescritos;
  final List<String> camposSinResolver;

  const ContextoEjecucion({
    this.tipo,
    this.record,
    this.camposDesdeBd = const {},
    this.camposSobreescritos = const [],
    this.camposSinResolver = const [],
  });

  /// Normaliza una colección de nombres de campo.
  ///
  /// El backend fue cambiando el formato entre versiones: puede llegar una
  /// lista, un mapa `campo → valor` (se toman las claves) o un string con los
  /// nombres separados por coma. Cualquier otra cosa se ignora.
  static List<String> _strList(dynamic raw) {
    final out = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final s = e?.toString() ?? '';
        if (s.isNotEmpty) out.add(s);
      }
    } else if (raw is Map) {
      for (final k in raw.keys) {
        final s = k?.toString() ?? '';
        if (s.isNotEmpty) out.add(s);
      }
    } else if (raw is String && raw.isNotEmpty) {
      for (final s in raw.split(',')) {
        final t = s.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  /// Normaliza una colección de campos con valor (`CAMPO` → valor).
  ///
  /// `camposDesdeBd` pasó de lista de nombres a mapa `campo → valor`: se
  /// aceptan ambos formatos y las respuestas viejas quedan con valor `null`.
  static Map<String, dynamic> _campoValorMap(dynamic raw) {
    final out = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final key = k?.toString() ?? '';
        if (key.isNotEmpty) out[key] = v;
      });
    } else if (raw is List) {
      for (final e in raw) {
        final key = e?.toString() ?? '';
        if (key.isNotEmpty) out[key] = null;
      }
    } else if (raw is String && raw.isNotEmpty) {
      for (final s in raw.split(',')) {
        final key = s.trim();
        if (key.isNotEmpty) out[key] = null;
      }
    }
    return out;
  }

  factory ContextoEjecucion.fromJson(Map<String, dynamic> json) {
    return ContextoEjecucion(
      tipo: json['tipo']?.toString(),
      record: json['record']?.toString(),
      camposDesdeBd: _campoValorMap(json['camposDesdeBd']),
      camposSobreescritos: _strList(json['camposSobreescritos']),
      camposSinResolver: _strList(json['camposSinResolver']),
    );
  }

  bool get isEmpty =>
      (tipo == null || tipo!.isEmpty) &&
      (record == null || record!.isEmpty) &&
      camposDesdeBd.isEmpty &&
      camposSobreescritos.isEmpty &&
      camposSinResolver.isEmpty;
}

/// Resultado devuelto por la ejecución del procedimiento dinámico.
class EjecucionResultado {
  final String? ambiente;
  final String? cdProcedimiento;

  /// `true` cuando el backend ejecutó el texto enviado desde el editor
  /// (`/ejecutar-borrador`) en vez del guardado en `PROCEDIMIENTODINAMICO`.
  final bool borrador;
  final String? inConfiguracion;
  final String? stProcedimiento;
  final String? orquestador;
  final ContextoEjecucion contexto;

  /// Valores OUT del procedimiento (`nombre` → valor).
  final Map<String, dynamic> salidas;

  /// Variables dinámicas resueltas (`#VARIABLE#` → valor con el que se
  /// reemplazó). Las respuestas viejas mandaban sólo la lista de nombres: en
  /// ese caso el valor queda en `null`.
  final Map<String, dynamic> variablesDinamicasUsadas;
  final List<String> traza;
  final String? errorOracle;
  final int? duracionMs;
  final bool rollback;
  final bool commitDetectado;

  /// JSON original de `data`, para inspección/copiado en la UI.
  final Map<String, dynamic> raw;

  const EjecucionResultado({
    this.ambiente,
    this.cdProcedimiento,
    this.borrador = false,
    this.inConfiguracion,
    this.stProcedimiento,
    this.orquestador,
    this.contexto = const ContextoEjecucion(),
    this.salidas = const {},
    this.variablesDinamicasUsadas = const {},
    this.traza = const [],
    this.errorOracle,
    this.duracionMs,
    this.rollback = false,
    this.commitDetectado = false,
    this.raw = const {},
  });

  static bool _bool(dynamic raw) {
    if (raw is bool) return raw;
    final s = raw?.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  factory EjecucionResultado.fromJson(Map<String, dynamic> json) {
    final rawSalidas = json['salidas'];
    final rawContexto = json['contexto'];
    final duracion = json['duracionMs'];

    return EjecucionResultado(
      ambiente: json['ambiente']?.toString(),
      cdProcedimiento: json['cdProcedimiento']?.toString(),
      borrador: _bool(json['borrador']),
      inConfiguracion: json['inConfiguracion']?.toString(),
      stProcedimiento: json['stProcedimiento']?.toString(),
      orquestador: json['orquestador']?.toString(),
      contexto: rawContexto is Map
          ? ContextoEjecucion.fromJson(
              rawContexto.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const ContextoEjecucion(),
      salidas: ContextoEjecucion._campoValorMap(rawSalidas),
      // Mapa `variable → valor` en el formato nuevo; lista de nombres en el
      // viejo. `_campoValorMap` acepta ambos.
      variablesDinamicasUsadas: ContextoEjecucion._campoValorMap(
        json['variablesDinamicasUsadas'],
      ),
      traza: ContextoEjecucion._strList(json['traza']),
      errorOracle: json['errorOracle']?.toString(),
      duracionMs: duracion is int
          ? duracion
          : int.tryParse(duracion?.toString() ?? ''),
      rollback: _bool(json['rollback']),
      commitDetectado: _bool(json['commitDetectado']),
      raw: json,
    );
  }

  bool get tieneError => errorOracle != null && errorOracle!.isNotEmpty;
}
