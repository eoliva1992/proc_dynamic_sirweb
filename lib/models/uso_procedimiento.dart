/// Modelos para el endpoint `/tools/procedimiento-dinamico/{cd}/usos`.
///
/// Esquema:
/// ```json
/// {
///   "usos": [
///     { "tabla": "...", "columna": "...",
///       "entidades": [{ "tipo": "...", "codigo": "...", "descripcion": "..." }],
///       "sql": "..." }
///   ],
///   "sqlOtrasTablas": [{ "tabla": "...", "sql": "...", "confirmada": true }]
/// }
/// ```
library;

/// Entidad concreta (evento, tabla, etc.) donde se detectó el uso.
class EntidadUso {
  final String tipo;
  final String? codigo;
  final String? descripcion;

  const EntidadUso({required this.tipo, this.codigo, this.descripcion});

  factory EntidadUso.fromJson(Map<String, dynamic> json) {
    return EntidadUso(
      tipo: json['tipo']?.toString() ?? '',
      codigo: json['codigo']?.toString(),
      descripcion: json['descripcion']?.toString(),
    );
  }

  /// Texto compacto: `TIPO 123 — Descripción`
  String get label {
    final head = [
      if (tipo.isNotEmpty) tipo,
      if (codigo != null && codigo!.isNotEmpty) codigo!,
    ].join(' ');
    if (descripcion != null && descripcion!.isNotEmpty) {
      return head.isEmpty ? descripcion! : '$head — ${descripcion!}';
    }
    return head;
  }

  String get searchText =>
      '$tipo ${codigo ?? ''} ${descripcion ?? ''}'.toUpperCase();
}

class UsoProcedimiento {
  final String tabla;
  final String columna;
  final List<EntidadUso> entidades;
  final String? sql;

  const UsoProcedimiento({
    required this.tabla,
    required this.columna,
    this.entidades = const [],
    this.sql,
  });

  factory UsoProcedimiento.fromJson(Map<String, dynamic> json) {
    final rawEntidades = json['entidades'] as List<dynamic>? ?? const [];
    return UsoProcedimiento(
      tabla: json['tabla']?.toString() ?? '',
      columna: json['columna']?.toString() ?? '',
      entidades: rawEntidades
          .whereType<Map<String, dynamic>>()
          .map(EntidadUso.fromJson)
          .toList(),
      sql: json['sql']?.toString(),
    );
  }
}

/// SQL asociado a otras tablas analizadas (confirmadas o no).
class SqlOtraTabla {
  final String tabla;
  final String? sql;
  final bool confirmada;

  const SqlOtraTabla({required this.tabla, this.sql, this.confirmada = false});

  factory SqlOtraTabla.fromJson(Map<String, dynamic> json) {
    final raw = json['confirmada'];
    return SqlOtraTabla(
      tabla: json['tabla']?.toString() ?? '',
      sql: json['sql']?.toString(),
      confirmada: raw is bool
          ? raw
          : (raw?.toString().toLowerCase() == 'true' || raw?.toString() == '1'),
    );
  }
}

class UsosProcedimiento {
  final List<UsoProcedimiento> usos;
  final List<SqlOtraTabla> sqlOtrasTablas;

  const UsosProcedimiento({
    this.usos = const [],
    this.sqlOtrasTablas = const [],
  });

  factory UsosProcedimiento.fromJson(Map<String, dynamic> json) {
    final rawUsos = json['usos'] as List<dynamic>? ?? const [];
    final rawOtras = json['sqlOtrasTablas'] as List<dynamic>? ?? const [];
    return UsosProcedimiento(
      usos: rawUsos
          .whereType<Map<String, dynamic>>()
          .map(UsoProcedimiento.fromJson)
          .toList(),
      sqlOtrasTablas: rawOtras
          .whereType<Map<String, dynamic>>()
          .map(SqlOtraTabla.fromJson)
          .toList(),
    );
  }

  bool get isEmpty => usos.isEmpty && sqlOtrasTablas.isEmpty;
}
