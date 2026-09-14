import 'plsql_symbols.dart' show stripPlSqlNoise;

// ── Tablas y alias referenciados en el fuente ────────────────────────────────
//
// Detecta las tablas/vistas usadas en el código (FROM, JOIN, UPDATE, INSERT,
// MERGE, DELETE) junto con sus alias, para poder ofrecer autocompletado de
// columnas: tanto `alias.` / `tabla.` como la lista de columnas de las tablas
// en uso.

/// Palabras que nunca son un alias.
const _kNoAlias = {
  'ON',
  'WHERE',
  'SET',
  'AND',
  'OR',
  'JOIN',
  'LEFT',
  'RIGHT',
  'INNER',
  'OUTER',
  'FULL',
  'CROSS',
  'GROUP',
  'ORDER',
  'HAVING',
  'START',
  'CONNECT',
  'UNION',
  'MINUS',
  'INTERSECT',
  'VALUES',
  'SELECT',
  'INTO',
  'FROM',
  'USING',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
  'LOOP',
  'FOR',
  'IF',
  'IS',
  'AS',
  'NOT',
  'EXISTS',
  'IN',
  'BULK',
  'COLLECT',
  'RETURNING',
  'PARTITION',
  'BY',
};

/// Corta el bloque de tablas de un `FROM` en la primera cláusula que lo cierra.
final _reFromClause = RegExp(
  r'\bFROM\s+([\s\S]*?)'
  r'(?=\bWHERE\b|\bGROUP\b|\bORDER\b|\bHAVING\b|\bCONNECT\b|\bSTART\b|'
  r'\bUNION\b|\bMINUS\b|\bINTERSECT\b|\bJOIN\b|\bLEFT\b|\bRIGHT\b|\bINNER\b|'
  r'\bFULL\b|\bCROSS\b|\bINTO\b|\bFOR\b|\bLOOP\b|;|\)|$)',
  caseSensitive: false,
);

/// Identificador de tabla, admitiendo esquema y comillas: `SIR."POLIZA"`.
const _kQualified = r'"?[A-Za-z_][\w$#]*"?(?:\s*\.\s*"?[A-Za-z_][\w$#]*"?)?';

/// Alias opcional que sigue al nombre de la tabla.
const _kAlias = r'(?:\s+(?:AS\s+)?([A-Za-z_]\w*))?';

final _reJoin = RegExp(
  r'\bJOIN\s+('
  '$_kQualified'
  r')'
  '$_kAlias',
  caseSensitive: false,
);

final _reDml = RegExp(
  r'\b(?:UPDATE|INSERT\s+INTO|MERGE\s+INTO|DELETE\s+FROM)\s+'
  r'('
  '$_kQualified'
  r')'
  '$_kAlias',
  caseSensitive: false,
);

/// Un elemento de la lista del FROM: `tabla [AS] alias`.
final _reTableRef = RegExp(
  r'^\s*('
  '$_kQualified'
  r')'
  '$_kAlias'
  r'\s*$',
  caseSensitive: false,
);

/// Quita el esquema (`SIR.POLIZA` → `POLIZA`) y normaliza a mayúsculas.
String _plain(String raw) {
  var t = raw.replaceAll('"', '').replaceAll(RegExp(r'\s+'), '');
  final dot = t.lastIndexOf('.');
  if (dot >= 0) t = t.substring(dot + 1);
  return t.toUpperCase();
}

/// Devuelve un mapa `alias|tabla → TABLA` con todas las tablas referenciadas.
///
/// Ejemplo: `FROM poliza p, cliente` → `{P: POLIZA, POLIZA: POLIZA,
/// CLIENTE: CLIENTE}`.
Map<String, String> extractSqlTables(String sql) {
  if (sql.trim().isEmpty) return const {};
  final src = stripPlSqlNoise(sql);
  final result = <String, String>{};

  void add(String? table, String? alias) {
    if (table == null || table.isEmpty) return;
    final t = _plain(table);
    if (t.isEmpty || _kNoAlias.contains(t)) return;
    result[t] = t;
    if (alias != null && alias.isNotEmpty) {
      final a = alias.toUpperCase();
      if (!_kNoAlias.contains(a)) result[a] = t;
    }
  }

  // Todas las cláusulas FROM del fuente (no sólo la primera).
  for (final m in _reFromClause.allMatches(src)) {
    final block = m.group(1) ?? '';
    // Subconsultas: se ignoran, sus tablas se detectan por su propio FROM.
    if (block.trimLeft().startsWith('(')) continue;
    for (final ref in block.split(',')) {
      final r = _reTableRef.firstMatch(ref.replaceAll('\n', ' '));
      if (r != null) add(r.group(1), r.group(2));
    }
  }
  for (final m in _reJoin.allMatches(src)) {
    add(m.group(1), m.group(2));
  }
  for (final m in _reDml.allMatches(src)) {
    add(m.group(1), m.group(2));
  }
  return result;
}

/// Tablas referenciadas mediante `tabla.columna%TYPE` en las declaraciones.
final _reTypeRef = RegExp(
  r'\b([A-Za-z_][\w$#]*)\s*\.\s*[A-Za-z_][\w$#]*\s*%\s*TYPE',
  caseSensitive: false,
);

/// Tablas usadas en anclajes `%TYPE` / `%ROWTYPE`.
Set<String> extractAnchoredTables(String sql) {
  if (sql.trim().isEmpty) return const {};
  final src = stripPlSqlNoise(sql);
  final out = <String>{};
  for (final m in _reTypeRef.allMatches(src)) {
    out.add(_plain(m.group(1)!));
  }
  for (final m in RegExp(
    r'\b([A-Za-z_][\w$#]*)\s*%\s*ROWTYPE',
    caseSensitive: false,
  ).allMatches(src)) {
    out.add(_plain(m.group(1)!));
  }
  out.removeWhere(_kNoAlias.contains);
  return out;
}

/// Todas las tablas cuyas columnas conviene tener cacheadas para el editor.
Set<String> tablesToPrefetch(String sql) => {
  ...extractSqlTables(sql).values,
  ...extractAnchoredTables(sql),
};
