/// Modelos de datos para restricciones, triggers e índices de tablas y vistas
/// en Oracle, obtenidos desde las vistas de catálogo del sistema (ALL_*).
library;

/// Tipo de restricción Oracle (`ALL_CONSTRAINTS.CONSTRAINT_TYPE`).
enum ConstraintType {
  primaryKey,
  foreignKey,
  unique,
  check,
  other;

  static ConstraintType fromOracleCode(String? code) =>
      switch (code?.toUpperCase()) {
        'P' => ConstraintType.primaryKey,
        'R' => ConstraintType.foreignKey,
        'U' => ConstraintType.unique,
        'C' => ConstraintType.check,
        _ => ConstraintType.other,
      };

  String get label => switch (this) {
    ConstraintType.primaryKey => 'PRIMARY KEY',
    ConstraintType.foreignKey => 'FOREIGN KEY',
    ConstraintType.unique => 'UNIQUE',
    ConstraintType.check => 'CHECK',
    ConstraintType.other => 'OTHER',
  };

  String get shortCode => switch (this) {
    ConstraintType.primaryKey => 'PK',
    ConstraintType.foreignKey => 'FK',
    ConstraintType.unique => 'UK',
    ConstraintType.check => 'CK',
    ConstraintType.other => '?',
  };
}

/// Información de una restricción (Constraint).
class TableConstraintInfo {
  final String name;
  final ConstraintType type;
  final String status;
  final List<String> columns;
  final String? searchCondition;
  final String? rOwner;
  final String? rConstraintName;
  final String? rTableName;

  const TableConstraintInfo({
    required this.name,
    required this.type,
    required this.status,
    required this.columns,
    this.searchCondition,
    this.rOwner,
    this.rConstraintName,
    this.rTableName,
  });

  bool get isEnabled => status.toUpperCase() == 'ENABLED';
}

/// Información de un disparador (Trigger).
class TableTriggerInfo {
  final String name;
  final String triggerType; // e.g. "BEFORE EACH ROW", "AFTER STATEMENT"
  final String triggeringEvent; // e.g. "INSERT OR UPDATE"
  final String status; // "ENABLED" o "DISABLED"
  final String owner;

  const TableTriggerInfo({
    required this.name,
    required this.triggerType,
    required this.triggeringEvent,
    required this.status,
    required this.owner,
  });

  bool get isEnabled => status.toUpperCase() == 'ENABLED';
}

/// Información de una columna en un índice.
class TableIndexColumnInfo {
  final String columnName;
  final int columnPosition;
  final String descend; // "ASC" o "DESC"

  const TableIndexColumnInfo({
    required this.columnName,
    required this.columnPosition,
    this.descend = 'ASC',
  });
}

/// Información de un índice.
class TableIndexInfo {
  final String name;
  final String uniqueness; // "UNIQUE" o "NONUNIQUE"
  final String indexType; // "NORMAL", "BITMAP", etc.
  final String status; // "VALID", "UNUSABLE", etc.
  final List<TableIndexColumnInfo> columns;

  const TableIndexInfo({
    required this.name,
    required this.uniqueness,
    required this.indexType,
    required this.status,
    required this.columns,
  });

  bool get isUnique => uniqueness.toUpperCase() == 'UNIQUE';
  bool get isValid => status.toUpperCase() == 'VALID';

  String get columnsFormatted => columns
      .map((c) => c.descend == 'DESC' ? '${c.columnName} DESC' : c.columnName)
      .join(', ');
}
