/// Detección de tipo de sentencia y separación de un script SQL/PL-SQL en
/// sentencias individuales.
///
/// No es un parser completo: usa heurísticas por palabra clave, suficientes
/// para decidir a qué servicio enrutar cada sentencia del editor.
library;

import '../models/sql_execution.dart';
import '../widgets/plsql_symbols.dart' show stripPlSqlNoise;

final _reLeadingWs = RegExp(r'^\s+');

/// Primer identificador/keyword de la sentencia (ya sin comentarios/strings).
String _firstKeyword(String stripped) {
  final trimmed = stripped.replaceFirst(_reLeadingWs, '');
  final m = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*').firstMatch(trimmed);
  return (m?.group(0) ?? '').toUpperCase();
}

final _reCreatePlsql = RegExp(
  r'^\s*CREATE\s+(OR\s+REPLACE\s+)?'
  r'(PROCEDURE|FUNCTION|PACKAGE(\s+BODY)?|TRIGGER|TYPE\s+BODY)\b',
  caseSensitive: false,
);

const _kDdlKeywords = {
  'CREATE',
  'ALTER',
  'DROP',
  'TRUNCATE',
  'GRANT',
  'REVOKE',
  'RENAME',
  'COMMENT',
};

const _kDmlKeywords = {'INSERT', 'UPDATE', 'DELETE', 'MERGE'};

/// Clasifica una sentencia ya recortada (una sola, sin `;` final necesario).
SqlStatementKind detectStatementKind(String statement) {
  final stripped = stripPlSqlNoise(statement).trim();
  if (stripped.isEmpty) return SqlStatementKind.unknown;

  if (RegExp(
    r'^\s*EXPLAIN\s+PLAN\b',
    caseSensitive: false,
  ).hasMatch(stripped)) {
    return SqlStatementKind.explainPlan;
  }
  if (_reCreatePlsql.hasMatch(stripped)) return SqlStatementKind.plsql;

  final kw = _firstKeyword(stripped);
  if (kw == 'SELECT' || kw == 'WITH') return SqlStatementKind.select;
  if (_kDmlKeywords.contains(kw)) return SqlStatementKind.dml;
  if (kw == 'BEGIN' || kw == 'DECLARE') return SqlStatementKind.plsql;
  if (_kDdlKeywords.contains(kw)) return SqlStatementKind.ddl;

  // Bloque anónimo sin `DECLARE` que arranca directo en otro punto, o texto
  // que contiene un `END;` de cierre: se asume PL/SQL.
  if (RegExp(r'\bEND\s*;?\s*$', caseSensitive: false).hasMatch(stripped) &&
      RegExp(r'\bBEGIN\b', caseSensitive: false).hasMatch(stripped)) {
    return SqlStatementKind.plsql;
  }
  return SqlStatementKind.unknown;
}

/// Palabras que abren un bloque que debe cerrar con su propio `END`
/// (para no cortar por el `;` interno de un bloque PL/SQL).
final _reBlockOpen = RegExp(
  r'\b(BEGIN|CASE|LOOP)\b|\bIF\b(?!\s*\().*?\bTHEN\b',
  caseSensitive: false,
);
final _reBlockClose = RegExp(r'\bEND\b', caseSensitive: false);

/// Separa un script en sentencias individuales.
///
/// Reglas:
/// - `;` cierra una sentencia sólo si no estamos dentro de un bloque PL/SQL
///   (se cuenta el anidamiento de `BEGIN/CASE/IF…THEN` vs `END`).
/// - Una línea que contiene únicamente `/` (convención SQL*Plus) cierra la
///   sentencia PL/SQL anterior sin necesitar `;`.
/// - Comentarios y literales de texto (incluso `q'[...]'`) no cuentan `;`.
List<SqlStatement> splitStatements(String script) {
  final stripped = stripPlSqlNoise(script);
  final statements = <SqlStatement>[];
  var start = 0;
  var depth = 0;

  int lineAt(int offset) => '\n'.allMatches(script.substring(0, offset)).length;

  void flush(int end) {
    final text = script.substring(start, end).trim();
    if (text.isNotEmpty) {
      final trimStart = start + script.substring(start, end).indexOf(text[0]);
      statements.add(
        SqlStatement(
          text: text,
          kind: detectStatementKind(text),
          startOffset: trimStart,
          endOffset: end,
          startLine: lineAt(trimStart),
          endLine: lineAt(end),
        ),
      );
    }
    start = end;
  }

  var i = 0;
  final n = stripped.length;
  while (i < n) {
    // Terminador SQL*Plus: línea que sólo contiene "/".
    if ((i == 0 || stripped[i - 1] == '\n') && stripped[i] == '/') {
      final rest = stripped.substring(i + 1);
      final eol = rest.indexOf('\n');
      final restOfLine = (eol == -1 ? rest : rest.substring(0, eol)).trim();
      if (restOfLine.isEmpty) {
        // Cierra cualquier sentencia pendiente (haya o no terminado ya en
        // ';'); si no queda nada pendiente, flush() es un no-op seguro.
        flush(i);
        depth = 0;
        start = i + 1;
        i++;
        continue;
      }
    }

    final remaining = stripped.substring(i);
    final openMatch = _reBlockOpen.matchAsPrefix(remaining);
    if (openMatch != null && openMatch.start == 0) {
      depth++;
      i += openMatch.end;
      continue;
    }
    final closeMatch = _reBlockClose.matchAsPrefix(remaining);
    if (closeMatch != null && closeMatch.start == 0) {
      if (depth > 0) depth--;
      i += closeMatch.end;
      continue;
    }

    if (stripped[i] == ';' && depth == 0) {
      flush(i + 1);
      i++;
      continue;
    }
    i++;
  }
  flush(n);
  return statements;
}

/// Sentencia bajo el cursor (o que contiene el rango `[selStart, selEnd]`).
SqlStatement? statementAtCursor(String script, int offset) {
  final statements = splitStatements(script);
  for (final s in statements) {
    if (offset >= s.startOffset && offset <= s.endOffset) return s;
  }
  return statements.isNotEmpty ? statements.last : null;
}
