/// Modelos para el Ejecutor SQL/PL-SQL: clasificación de sentencias,
/// resultado de un SELECT, resultado de un DML/DDL, plan de ejecución y
/// entradas del panel de mensajes/historial.
library;

/// Tipo de sentencia detectado por `sql_statement_analyzer.dart`.
enum SqlStatementKind { select, dml, ddl, plsql, command, explainPlan, unknown }

extension SqlStatementKindLabel on SqlStatementKind {
  String get label => switch (this) {
    SqlStatementKind.select => 'SELECT',
    SqlStatementKind.dml => 'DML',
    SqlStatementKind.ddl => 'DDL',
    SqlStatementKind.plsql => 'PL/SQL',
    SqlStatementKind.command => 'COMMAND',
    SqlStatementKind.explainPlan => 'EXPLAIN PLAN',
    SqlStatementKind.unknown => '?',
  };
}

/// Una sentencia individual dentro de un script con varias, separadas por
/// `;` o por `/` (convención SQL*Plus para bloques PL/SQL).
class SqlStatement {
  const SqlStatement({
    required this.text,
    required this.kind,
    required this.startOffset,
    required this.endOffset,
    required this.startLine,
    required this.endLine,
  });

  final String text;
  final SqlStatementKind kind;
  final int startOffset;
  final int endOffset;
  final int startLine;
  final int endLine;
}

/// Columna devuelta por un SELECT.
class SqlColumn {
  const SqlColumn({required this.name, required this.dataType});

  final String name;
  final String dataType;

  factory SqlColumn.fromJson(Map<String, dynamic> json) => SqlColumn(
    name: json['name']?.toString() ?? '',
    dataType: json['dataType']?.toString() ?? '',
  );
}

/// Resultado de `POST /tools/sql/query`.
class SqlQueryResult {
  const SqlQueryResult({
    required this.columns,
    required this.rows,
    required this.returnedRows,
    required this.truncated,
    required this.durationMs,
  });

  final List<SqlColumn> columns;
  final List<List<dynamic>> rows;
  final int returnedRows;
  final bool truncated;
  final int durationMs;

  factory SqlQueryResult.fromJson(Map<String, dynamic> json) {
    final rawColumns = json['columns'] as List<dynamic>? ?? const [];
    final rawRows = json['rows'] as List<dynamic>? ?? const [];
    return SqlQueryResult(
      columns: rawColumns
          .whereType<Map<String, dynamic>>()
          .map(SqlColumn.fromJson)
          .toList(),
      rows: rawRows
          .map((r) => (r as List<dynamic>? ?? const []).toList())
          .toList(),
      returnedRows: (json['returnedRows'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] as bool? ?? false,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  static const empty = SqlQueryResult(
    columns: [],
    rows: [],
    returnedRows: 0,
    truncated: false,
    durationMs: 0,
  );

  /// Crea una copia agregando más filas (útil para paginación incremental).
  SqlQueryResult appendRows(
    List<List<dynamic>> newRows, {
    required bool truncated,
    required int additionalDurationMs,
  }) {
    final combined = List<List<dynamic>>.of(rows)..addAll(newRows);
    return SqlQueryResult(
      columns: columns,
      rows: combined,
      returnedRows: combined.length,
      truncated: truncated,
      durationMs: durationMs + additionalDurationMs,
    );
  }
}

/// Un resultado de SELECT con su etiqueta, para mostrar varias ejecuciones
/// como sub-pestañas dentro de la pestaña "Resultados".
class SqlNamedResult {
  const SqlNamedResult({
    required this.id,
    required this.label,
    required this.result,
    this.statementText = '',
  });

  final int id;
  final String label;
  final SqlQueryResult result;

  /// Texto SQL de la sentencia que originó este resultado.
  final String statementText;

  /// Retorna una copia con el resultado actualizado.
  SqlNamedResult withResult(SqlQueryResult updatedResult) {
    return SqlNamedResult(
      id: id,
      label: label,
      result: updatedResult,
      statementText: statementText,
    );
  }
}

/// Resultado de un DML o DDL ejecutado vía `POST /tools/sql/statement`
/// (`data.dml` o `data.ddl` según el `kind` de la respuesta).
///
/// Mientras `sessionId` no sea `null`, la transacción sigue abierta en el
/// backend hasta que se llame a `commitSession`/`rollbackSession`.
class SqlDmlResult {
  const SqlDmlResult({
    required this.rowsAffected,
    required this.durationMs,
    this.message,
    this.sessionId,
    this.pendingCommit = false,
  });

  final int rowsAffected;
  final int durationMs;
  final String? message;
  final String? sessionId;
  final bool pendingCommit;

  factory SqlDmlResult.fromJson(Map<String, dynamic> json) => SqlDmlResult(
    rowsAffected: (json['rowsAffected'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    message: json['message']?.toString(),
    sessionId: json['sessionId']?.toString(),
    pendingCommit: json['pendingCommit'] as bool? ?? false,
  );
}

/// Un error de compilación reportado al ejecutar DDL (`data.ddl.errors[]`).
class SqlDdlError {
  const SqlDdlError({this.line, this.position, this.text, this.attribute});

  final int? line;
  final int? position;
  final String? text;
  final String? attribute;

  factory SqlDdlError.fromJson(Map<String, dynamic> json) {
    int? parseNum(List<String> keys) {
      for (final k in keys) {
        final val = json[k];
        if (val is num) return val.toInt();
        if (val != null) {
          final parsed = int.tryParse(val.toString());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    String? parseString(List<String> keys) {
      for (final k in keys) {
        final val = json[k];
        if (val != null && val.toString().trim().isNotEmpty) {
          return val.toString().trim();
        }
      }
      return null;
    }

    return SqlDdlError(
      line: parseNum(const ['line', 'LINE', 'Line']),
      position: parseNum(const ['position', 'POSITION', 'Position', 'col', 'COL', 'column', 'COLUMN']),
      text: parseString(const ['text', 'TEXT', 'Text', 'message', 'MESSAGE', 'Message', 'msg', 'MSG']),
      attribute: parseString(const ['attribute', 'ATTRIBUTE', 'Attribute', 'severity', 'SEVERITY']) ?? 'ERROR',
    );
  }

  @override
  String toString() {
    final loc = line != null ? (position != null ? 'L$line:$position' : 'L$line') : null;
    final parts = [?loc, ?attribute, ?text];
    return parts.join(' ');
  }
}

/// Resultado de un DDL ejecutado vía `POST /tools/sql/statement`
/// (`data.ddl`).
class SqlDdlResult {
  const SqlDdlResult({
    required this.ambiente,
    this.objectName,
    this.objectType,
    required this.confirmed,
    required this.autoCommitPossible,
    this.errors = const [],
    required this.durationMs,
  });

  final String ambiente;
  final String? objectName;
  final String? objectType;
  final bool confirmed;
  final bool autoCommitPossible;
  final List<SqlDdlError> errors;
  final int durationMs;

  factory SqlDdlResult.fromJson(Map<String, dynamic> json) {
    final rawCandidates = <dynamic>[
      json['errors'],
      json['compileErrors'],
      json['compilationErrors'],
      json['compile_errors'],
      json['data'],
    ];

    List<SqlDdlError> parseErrors(dynamic value) {
      if (value == null) return const [];
      if (value is List) {
        final list = <SqlDdlError>[];
        for (final item in value) {
          list.addAll(parseErrors(item));
        }
        return list;
      }
      if (value is Map<String, dynamic>) {
        final err = SqlDdlError.fromJson(value);
        if (err.text != null && err.text!.isNotEmpty) return [err];
        return const [];
      }
      if (value is Map) {
        final err = SqlDdlError.fromJson(Map<String, dynamic>.from(value));
        if (err.text != null && err.text!.isNotEmpty) return [err];
        return const [];
      }
      if (value is String && value.trim().isNotEmpty) {
        final list = <SqlDdlError>[];
        final pattern = RegExp(r'^(\d+)/(\d+)\s+(.+)$', multiLine: true);
        for (final match in pattern.allMatches(value)) {
          list.add(
            SqlDdlError(
              line: int.tryParse(match.group(1)!),
              position: int.tryParse(match.group(2)!),
              text: match.group(3)!.trim(),
              attribute: 'ERROR',
            ),
          );
        }
        if (list.isNotEmpty) return list;

        for (final line in value.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.contains('PLS-') ||
              trimmed.contains('ORA-') ||
              trimmed.contains('PL/SQL:')) {
            list.add(SqlDdlError(text: trimmed, attribute: 'ERROR'));
          }
        }
        return list;
      }
      return const [];
    }

    final errors = <SqlDdlError>[];
    for (final candidate in rawCandidates) {
      final parsed = parseErrors(candidate);
      if (parsed.isNotEmpty) {
        errors.addAll(parsed);
        break;
      }
    }

    return SqlDdlResult(
      ambiente: json['ambiente']?.toString() ?? '',
      objectName: json['objectName']?.toString(),
      objectType: json['objectType']?.toString(),
      confirmed: json['confirmed'] as bool? ?? false,
      autoCommitPossible: json['autoCommitPossible'] as bool? ?? false,
      errors: errors,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Resultado de un bloque PL/SQL ejecutado vía `POST /tools/sql/statement`
/// (`data.plSql`).
class SqlPlSqlResult {
  const SqlPlSqlResult({
    this.sessionId,
    this.outputs = const {},
    this.dbmsOutput = const [],
    this.pendingCommit = false,
    required this.durationMs,
  });

  final String? sessionId;
  final Map<String, dynamic> outputs;
  final List<String> dbmsOutput;
  final bool pendingCommit;
  final int durationMs;

  factory SqlPlSqlResult.fromJson(Map<String, dynamic> json) {
    final rawOutputs = json['outputs'] as Map<String, dynamic>? ?? const {};
    final rawDbmsOutput = json['dbmsOutput'] as List? ?? const [];
    return SqlPlSqlResult(
      sessionId: json['sessionId']?.toString(),
      outputs: rawOutputs,
      dbmsOutput: rawDbmsOutput.map((e) => e.toString()).toList(),
      pendingCommit: json['pendingCommit'] as bool? ?? false,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Columna devuelta por un comando cliente (por ejemplo `DESC`).
class SqlCommandColumn {
  const SqlCommandColumn({
    required this.columnName,
    required this.dataType,
    this.dataLength,
    this.dataPrecision,
    this.dataScale,
    this.nullable = true,
  });

  final String columnName;
  final String dataType;
  final int? dataLength;
  final int? dataPrecision;
  final int? dataScale;
  final bool nullable;

  factory SqlCommandColumn.fromJson(Map<String, dynamic> json) => SqlCommandColumn(
    columnName: json['columnName']?.toString() ?? '',
    dataType: json['dataType']?.toString() ?? '',
    dataLength: (json['dataLength'] as num?)?.toInt(),
    dataPrecision: (json['dataPrecision'] as num?)?.toInt(),
    dataScale: (json['dataScale'] as num?)?.toInt(),
    nullable: json['nullable'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'columnName': columnName,
    'dataType': dataType,
    'dataLength': dataLength,
    'dataPrecision': dataPrecision,
    'dataScale': dataScale,
    'nullable': nullable,
  };
}

/// Resultado de un comando cliente ejecutado vía `POST /tools/sql/statement`
/// (`data.command`).
class SqlCommandResult {
  const SqlCommandResult({
    required this.command,
    required this.output,
    this.columns = const [],
    this.durationMs = 0,
  });

  final String command;
  final String output;
  final List<SqlCommandColumn> columns;
  final int durationMs;

  factory SqlCommandResult.fromJson(
    Map<String, dynamic> json, {
    int durationMs = 0,
  }) {
    final rawData = json['data'] as List<dynamic>? ?? const [];
    return SqlCommandResult(
      command: json['command']?.toString() ?? '',
      output: json['output']?.toString() ?? '',
      columns: rawData
          .whereType<Map<String, dynamic>>()
          .map(SqlCommandColumn.fromJson)
          .toList(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? durationMs,
    );
  }

  /// Convierte el resultado estructurado de `DESC` en un `SqlQueryResult`
  /// para renderizarlo directamente en la grilla interactiva de resultados.
  SqlQueryResult toSqlQueryResult() {
    if (columns.isEmpty) {
      return SqlQueryResult(
        columns: const [
          SqlColumn(name: 'SALIDA', dataType: 'VARCHAR2'),
        ],
        rows: [
          [output],
        ],
        returnedRows: 1,
        truncated: false,
        durationMs: durationMs,
      );
    }

    final queryColumns = const [
      SqlColumn(name: 'COLUMNA', dataType: 'VARCHAR2'),
      SqlColumn(name: 'TIPO', dataType: 'VARCHAR2'),
      SqlColumn(name: 'LONGITUD', dataType: 'NUMBER'),
      SqlColumn(name: 'PRECISIÓN', dataType: 'NUMBER'),
      SqlColumn(name: 'ESCALA', dataType: 'NUMBER'),
      SqlColumn(name: 'NULO?', dataType: 'VARCHAR2'),
    ];

    final rows = <List<dynamic>>[];
    for (final col in columns) {
      rows.add([
        col.columnName,
        col.dataType,
        col.dataLength,
        col.dataPrecision,
        col.dataScale,
        col.nullable ? 'Y' : 'N',
      ]);
    }

    return SqlQueryResult(
      columns: queryColumns,
      rows: rows,
      returnedRows: rows.length,
      truncated: false,
      durationMs: durationMs,
    );
  }
}

/// Un nodo del plan de ejecución (`EXPLAIN PLAN` de Oracle).
class SqlExplainPlanNode {
  const SqlExplainPlanNode({
    required this.id,
    this.parentId,
    required this.operation,
    this.options,
    this.objectName,
    this.objectOwner,
    this.objectType,
    this.cost,
    this.cardinality,
    this.bytes,
    required this.depth,
    this.accessPredicate,
    this.filterPredicate,
    this.children = const [],
  });

  final int id;
  final int? parentId;
  final String operation;
  final String? options;
  final String? objectName;
  final String? objectOwner;
  final String? objectType;
  final int? cost;
  final int? cardinality;
  final int? bytes;
  final int depth;
  final String? accessPredicate;
  final String? filterPredicate;
  final List<SqlExplainPlanNode> children;

  factory SqlExplainPlanNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final childrenList = rawChildren is List
        ? rawChildren
              .whereType<Map<String, dynamic>>()
              .map((c) => SqlExplainPlanNode.fromJson(c))
              .toList()
        : const <SqlExplainPlanNode>[];

    return SqlExplainPlanNode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      parentId: (json['parentId'] as num?)?.toInt(),
      operation: json['operation']?.toString() ?? '',
      options: json['options']?.toString(),
      objectName: json['objectName']?.toString(),
      objectOwner: json['objectOwner']?.toString(),
      objectType: json['objectType']?.toString(),
      cost: (json['cost'] as num?)?.toInt(),
      cardinality: (json['cardinality'] as num?)?.toInt(),
      bytes: (json['bytes'] as num?)?.toInt(),
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      accessPredicate:
          json['accessPredicates']?.toString() ??
          json['accessPredicate']?.toString(),
      filterPredicate:
          json['filterPredicates']?.toString() ??
          json['filterPredicate']?.toString(),
      children: childrenList,
    );
  }
}

/// Resultado completo de `POST /tools/sql/explain`.
class SqlExplainResult {
  const SqlExplainResult({
    required this.ambiente,
    required this.rows,
    required this.text,
    required this.tree,
    required this.durationMs,
  });

  final String ambiente;
  final List<SqlExplainPlanNode> rows;
  final List<String> text;
  final List<SqlExplainPlanNode> tree;
  final int durationMs;

  factory SqlExplainResult.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List? ?? [];
    final rawTree = json['tree'] as List? ?? [];
    final rawText = json['text'] as List? ?? [];

    return SqlExplainResult(
      ambiente: json['ambiente']?.toString() ?? '',
      rows: rawRows
          .whereType<Map<String, dynamic>>()
          .map((r) => SqlExplainPlanNode.fromJson(r))
          .toList(),
      text: rawText.map((t) => t.toString()).toList(),
      tree: rawTree
          .whereType<Map<String, dynamic>>()
          .map((t) => SqlExplainPlanNode.fromJson(t))
          .toList(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Estado de una entrada del panel de Mensajes/Historial.
enum SqlLogStatus { running, success, warning, error }

/// Una entrada del panel de Mensajes o del Historial de ejecución.
class SqlExecutionLogEntry {
  SqlExecutionLogEntry({
    required this.id,
    required this.timestamp,
    required this.ambiente,
    required this.kind,
    required this.statementPreview,
    required this.status,
    this.message,
    this.durationMs,
    this.rowsAffectedOrReturned,
  });

  final int id;
  final DateTime timestamp;
  final String ambiente;
  final SqlStatementKind kind;
  final String statementPreview;
  SqlLogStatus status;
  String? message;
  int? durationMs;
  int? rowsAffectedOrReturned;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'ambiente': ambiente,
    'kind': kind.name,
    'statementPreview': statementPreview,
    'status': status.name,
    'message': message,
    'durationMs': durationMs,
    'rowsAffectedOrReturned': rowsAffectedOrReturned,
  };

  factory SqlExecutionLogEntry.fromJson(Map<String, dynamic> json) {
    return SqlExecutionLogEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      ambiente: json['ambiente']?.toString() ?? '',
      kind: SqlStatementKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => SqlStatementKind.unknown,
      ),
      statementPreview: json['statementPreview']?.toString() ?? '',
      status: SqlLogStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SqlLogStatus.success,
      ),
      message: json['message']?.toString(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      rowsAffectedOrReturned: (json['rowsAffectedOrReturned'] as num?)?.toInt(),
    );
  }
}
