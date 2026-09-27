/// Generación de sentencias INSERT/UPDATE/MERGE a partir de filas de un
/// `SqlQueryResult` (resultado de un SELECT ejecutado en el editor).
library;

import '../models/sql_execution.dart';

/// Tipos de dato que se tratan como numéricos (sin comillas) al generar SQL.
bool _isNumericType(String dataType) {
  final t = dataType.toUpperCase();
  return t.contains('NUMBER') ||
      t.contains('FLOAT') ||
      t.contains('INT') ||
      t.contains('DECIMAL');
}

String _sqlLiteral(dynamic value, String dataType) {
  if (value == null) return 'NULL';
  if (_isNumericType(dataType)) return value.toString();
  final escaped = value.toString().replaceAll("'", "''");
  return "'$escaped'";
}

/// `INSERT INTO tabla (COL1, COL2) VALUES (v1, v2);` por cada fila indicada.
String generateInsert(
  String table,
  SqlQueryResult result,
  List<int> rowIndexes,
) {
  final cols = result.columns.map((c) => c.name).join(', ');
  final buf = StringBuffer();
  for (final idx in rowIndexes) {
    final row = result.rows[idx];
    final values = [
      for (var i = 0; i < result.columns.length; i++)
        _sqlLiteral(row[i], result.columns[i].dataType),
    ].join(', ');
    buf.writeln('INSERT INTO $table ($cols) VALUES ($values);');
  }
  return buf.toString().trimRight();
}

/// `UPDATE tabla SET COL1 = v1 WHERE KEY1 = k1;` por cada fila indicada.
///
/// Las columnas en [keyColumns] se usan en el `WHERE` y se excluyen del `SET`.
String generateUpdate(
  String table,
  SqlQueryResult result,
  List<int> rowIndexes,
  List<String> keyColumns,
) {
  final keys = keyColumns.map((k) => k.toUpperCase()).toSet();
  final buf = StringBuffer();
  for (final idx in rowIndexes) {
    final row = result.rows[idx];
    final setParts = <String>[];
    final whereParts = <String>[];
    for (var i = 0; i < result.columns.length; i++) {
      final col = result.columns[i];
      final literal = _sqlLiteral(row[i], col.dataType);
      if (keys.contains(col.name.toUpperCase())) {
        whereParts.add('${col.name} = $literal');
      } else {
        setParts.add('${col.name} = $literal');
      }
    }
    if (whereParts.isEmpty) continue;
    buf.writeln(
      'UPDATE $table SET ${setParts.join(', ')} '
      'WHERE ${whereParts.join(' AND ')};',
    );
  }
  return buf.toString().trimRight();
}

/// `MERGE INTO tabla t USING (...) s ON (...) WHEN MATCHED THEN UPDATE ...
/// WHEN NOT MATCHED THEN INSERT ...;` por cada fila indicada.
String generateMerge(
  String table,
  SqlQueryResult result,
  List<int> rowIndexes,
  List<String> keyColumns,
) {
  final keys = keyColumns.map((k) => k.toUpperCase()).toSet();
  final buf = StringBuffer();
  for (final idx in rowIndexes) {
    final row = result.rows[idx];
    final selectParts = <String>[];
    final onParts = <String>[];
    final updateParts = <String>[];
    for (var i = 0; i < result.columns.length; i++) {
      final col = result.columns[i];
      final literal = _sqlLiteral(row[i], col.dataType);
      selectParts.add('$literal AS ${col.name}');
      if (keys.contains(col.name.toUpperCase())) {
        onParts.add('t.${col.name} = s.${col.name}');
      } else {
        updateParts.add('t.${col.name} = s.${col.name}');
      }
    }
    if (onParts.isEmpty) continue;
    final cols = result.columns.map((c) => c.name).join(', ');
    final sourceCols = result.columns.map((c) => 's.${c.name}').join(', ');
    buf.writeln(
      'MERGE INTO $table t\n'
      'USING (SELECT ${selectParts.join(', ')} FROM DUAL) s\n'
      'ON (${onParts.join(' AND ')})\n'
      'WHEN MATCHED THEN UPDATE SET ${updateParts.join(', ')}\n'
      'WHEN NOT MATCHED THEN INSERT ($cols) VALUES ($sourceCols);',
    );
  }
  return buf.toString().trimRight();
}
