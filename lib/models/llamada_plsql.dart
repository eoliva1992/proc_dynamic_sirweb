/// Modelos del endpoint de invocación libre de objetos PL/SQL:
///
/// `POST /tools/plsql/llamada`
///
/// Permite ejecutar cualquier `PROCEDURE`, `FUNCTION` o miembro de un
/// `PACKAGE` mandando la firma con los valores de los parámetros de entrada.
/// El backend resuelve la firma real en Oracle, completa los parámetros `OUT`
/// que falten, ejecuta dentro de un bloque anónimo y hace ROLLBACK al final
/// (salvo que el objeto haya hecho COMMIT, que se reporta aparte).
///
/// Request:
/// ```json
/// {
///   "llamada": "SIR.PCK_PROCEDIMIENTO.BUSCA_TEXTO_PROC(P_CD_PROC => 'DR_TEST');",
///   "ambiente": null, "overload": null, "timeoutSegundos": null
/// }
/// ```
///
/// Response: `{ success, message, error, data: { ...LlamadaResultado } }`
///
/// ```json
/// {
///   "ambiente": "Desa",
///   "objeto": "SIR.PCK_PROCEDIMIENTO.BUSCA_TEXTO_PROC",
///   "llamada": "…(P_CD_PROC => v_1, P_TEXTO => v_2, P_ERROR => v_3);",
///   "tipoObjeto": "PROCEDURE", "overload": null,
///   "firma": [
///     { "nombre": "P_CD_PROC", "posicion": 1, "modo": "IN",
///       "tipo": "VARCHAR2", "tieneDefault": false, "noSoportado": null }
///   ],
///   "argumentosEnviados": { "P_CD_PROC": "DR_TEST" },
///   "argumentosSalida": { "P_TEXTO": null, "P_ERROR": "…" },
///   "retorno": null, "traza": [], "errorOracle": null, "codigoError": null,
///   "duracionMs": 83, "duracionLlamadaMs": 1,
///   "rollback": true, "commitDetectado": false
/// }
/// ```
library;

/// Parámetros del endpoint `POST /tools/plsql/llamada`.
class LlamadaRequest {
  /// Firma a ejecutar, p. ej.
  /// `SIR.PCK_X.MI_PROC(P_UNO => 1, P_DOS => 'texto');`
  ///
  /// Los parámetros `OUT` pueden omitirse: el backend los completa solo.
  final String llamada;

  /// `null` ⇒ ambiente por defecto del servidor (Desa).
  final String? ambiente;

  /// Desambigua subprogramas sobrecargados (`ALL_ARGUMENTS.OVERLOAD`).
  final int? overload;
  final int? timeoutSegundos;

  const LlamadaRequest({
    required this.llamada,
    this.ambiente,
    this.overload,
    this.timeoutSegundos,
  });

  /// El backend espera el contrato completo: los `null` se envían explícitos.
  Map<String, dynamic> toJson() => {
    'llamada': llamada,
    'ambiente': ambiente,
    'overload': overload,
    'timeoutSegundos': timeoutSegundos,
  };
}

/// Un parámetro de la firma real resuelta por el backend en Oracle.
class ParametroFirma {
  final String nombre;
  final int posicion;

  /// `IN`, `OUT`, `IN/OUT` (Oracle también devuelve `IN OUT`).
  final String modo;
  final String tipo;
  final bool tieneDefault;

  /// Motivo por el que el tipo no puede enviarse desde el bloque anónimo
  /// (`PL/SQL RECORD`, `REF CURSOR`, `PL/SQL BOOLEAN`…). `null` si es usable.
  final String? noSoportado;

  const ParametroFirma({
    required this.nombre,
    required this.posicion,
    required this.modo,
    required this.tipo,
    this.tieneDefault = false,
    this.noSoportado,
  });

  factory ParametroFirma.fromJson(Map<String, dynamic> json) {
    final pos = json['posicion'] ?? json['position'];
    return ParametroFirma(
      nombre: (json['nombre'] ?? json['argumentName'] ?? '').toString(),
      posicion: pos is int ? pos : int.tryParse(pos?.toString() ?? '') ?? 0,
      modo: (json['modo'] ?? json['inOut'] ?? 'IN').toString().toUpperCase(),
      tipo: (json['tipo'] ?? json['dataType'] ?? '').toString().toUpperCase(),
      tieneDefault: json['tieneDefault'] == true,
      noSoportado: json['noSoportado']?.toString(),
    );
  }

  /// Posición 0 es el valor de retorno de las funciones.
  bool get esRetorno => posicion == 0 || nombre.toLowerCase() == '(return)';

  /// `IN` e `IN OUT` piden valor al usuario; `OUT` los completa el backend.
  bool get esEntrada => !esRetorno && modo.contains('IN');
  bool get esSalida => esRetorno || modo.contains('OUT');

  /// Sólo estos tipos se pueden mandar como literal en la llamada.
  bool get esNumerico => const {
    'NUMBER',
    'INTEGER',
    'INT',
    'SMALLINT',
    'DECIMAL',
    'NUMERIC',
    'FLOAT',
    'REAL',
    'DOUBLE PRECISION',
    'BINARY_INTEGER',
    'BINARY_FLOAT',
    'BINARY_DOUBLE',
    'PLS_INTEGER',
    'NATURAL',
    'POSITIVE',
  }.contains(tipo);

  /// `true` si es un entero estricto sin decimales (INTEGER, PLS_INTEGER, etc.).
  bool get esEntero => const {
    'INTEGER',
    'INT',
    'SMALLINT',
    'BINARY_INTEGER',
    'PLS_INTEGER',
    'NATURAL',
    'POSITIVE',
  }.contains(tipo);

  /// Tipos de fecha/hora de Oracle: se editan con selector de fecha y se
  /// mandan como `TO_DATE('dd/mm/yyyy', 'dd/mm/yyyy')` (o `TO_TIMESTAMP` para
  /// los que llevan hora).
  bool get esFecha => const {
    'DATE',
    'TIMESTAMP',
    'TIMESTAMP WITH TIME ZONE',
    'TIMESTAMP WITH LOCAL TIME ZONE',
  }.contains(tipo);

  /// `true` si el tipo de fecha incluye hora (todo salvo `DATE`, que en Oracle
  /// también tiene hora, pero acá sólo se pide fecha para simplificar la UI).
  bool get esFechaConHora => tipo.startsWith('TIMESTAMP');

  /// `true` cuando el backend marcó el tipo como no enviable.
  bool get bloqueado => noSoportado != null && noSoportado!.isNotEmpty;
}

/// Resultado de la invocación del objeto PL/SQL.
class LlamadaResultado {
  final String? ambiente;

  /// Nombre completo del objeto tal como lo resolvió el backend.
  final String? objeto;

  /// Llamada normalizada que realmente se ejecutó (con los literales ya
  /// reemplazados por variables `v_N` del bloque anónimo).
  final String? llamada;
  final String? tipoObjeto;
  final int? overload;
  final List<ParametroFirma> firma;

  /// Valores que se enviaron (`parámetro` → valor).
  final Map<String, dynamic> argumentosEnviados;

  /// Valores devueltos por los parámetros `OUT` / `IN OUT`.
  final Map<String, dynamic> argumentosSalida;

  /// Valor de retorno cuando el objeto es una `FUNCTION`.
  final dynamic retorno;
  final List<String> traza;
  final String? errorOracle;
  final String? codigoError;

  /// Tiempo total del endpoint (incluye resolver la firma).
  final int? duracionMs;

  /// Tiempo del `EXECUTE IMMEDIATE` del bloque anónimo.
  final int? duracionLlamadaMs;
  final bool rollback;
  final bool commitDetectado;

  /// JSON original de `data`, para inspección/copiado en la UI.
  final Map<String, dynamic> raw;

  const LlamadaResultado({
    this.ambiente,
    this.objeto,
    this.llamada,
    this.tipoObjeto,
    this.overload,
    this.firma = const [],
    this.argumentosEnviados = const {},
    this.argumentosSalida = const {},
    this.retorno,
    this.traza = const [],
    this.errorOracle,
    this.codigoError,
    this.duracionMs,
    this.duracionLlamadaMs,
    this.rollback = false,
    this.commitDetectado = false,
    this.raw = const {},
  });

  static bool _bool(dynamic raw) {
    if (raw is bool) return raw;
    final s = raw?.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  static int? _int(dynamic raw) =>
      raw is int ? raw : int.tryParse(raw?.toString() ?? '');

  static Map<String, dynamic> _map(dynamic raw) {
    final out = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final key = k?.toString() ?? '';
        if (key.isNotEmpty) out[key] = v;
      });
    }
    return out;
  }

  static List<String> _strList(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if ((e?.toString() ?? '').isNotEmpty) e.toString(),
    ];
  }

  factory LlamadaResultado.fromJson(Map<String, dynamic> json) {
    final rawFirma = json['firma'];
    return LlamadaResultado(
      ambiente: json['ambiente']?.toString(),
      objeto: json['objeto']?.toString(),
      llamada: json['llamada']?.toString(),
      tipoObjeto: json['tipoObjeto']?.toString(),
      overload: _int(json['overload']),
      firma: rawFirma is List
          ? [
              for (final e in rawFirma)
                if (e is Map)
                  ParametroFirma.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v)),
                  ),
            ]
          : const [],
      argumentosEnviados: _map(json['argumentosEnviados']),
      argumentosSalida: _map(json['argumentosSalida']),
      retorno: json['retorno'],
      traza: _strList(json['traza']),
      errorOracle: json['errorOracle']?.toString(),
      codigoError: json['codigoError']?.toString(),
      duracionMs: _int(json['duracionMs']),
      duracionLlamadaMs: _int(json['duracionLlamadaMs']),
      rollback: _bool(json['rollback']),
      commitDetectado: _bool(json['commitDetectado']),
      raw: json,
    );
  }

  bool get tieneError => errorOracle != null && errorOracle!.isNotEmpty;
  bool get esFuncion => (tipoObjeto ?? '').toUpperCase().contains('FUNCTION');
}
