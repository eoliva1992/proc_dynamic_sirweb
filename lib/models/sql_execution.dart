/// Modelos para el Ejecutor SQL/PL-SQL: clasificación de sentencias,
/// resultado de un SELECT, resultado de un DML/DDL, plan de ejecución y
/// entradas del panel de mensajes/historial.
library;

/// Tipo de sentencia detectado por `sql_statement_analyzer.dart`.
enum SqlStatementKind { select, dml, ddl, plsql, explainPlan, unknown }

extension SqlStatementKindLabel on SqlStatementKind {
  String get label => switch (this) {
    SqlStatementKind.select => 'SELECT',
    SqlStatementKind.dml => 'DML',
    SqlStatementKind.ddl => 'DDL',
    SqlStatementKind.plsql => 'PL/SQL',
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
}

/// Resultado de un DML/DDL (forma provisoria: se ajustará cuando el backend
/// defina el contrato real del endpoint).
class SqlDmlResult {
  const SqlDmlResult({
    required this.rowsAffected,
    required this.durationMs,
    this.message,
  });

  final int rowsAffected;
  final int durationMs;
  final String? message;

  factory SqlDmlResult.fromJson(Map<String, dynamic> json) => SqlDmlResult(
    rowsAffected: (json['rowsAffected'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    message: json['message']?.toString(),
  );
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
