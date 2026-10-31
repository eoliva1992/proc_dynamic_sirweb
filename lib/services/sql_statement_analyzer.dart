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
  r'(NOFORCE\s+|FORCE\s+)?'
  r'(EDITIONABLE\s+|NONEDITIONABLE\s+)?'
  r'(PROCEDURE|FUNCTION|PACKAGE(\s+BODY)?|TRIGGER|TYPE(\s+BODY)?)\b',
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

  // Comandos cliente compatibles (SQL*Plus / SQL Developer), como DESC o DESCRIBE.
  if (RegExp(
    r'^\s*(DESC|DESCRIBE)\b',
    caseSensitive: false,
  ).hasMatch(stripped)) {
    return SqlStatementKind.command;
  }

  // CREATE de objetos almacenados es DDL, aunque su fuente contenga BEGIN/END.
  // Enrutándolo por DDL, executeDdl envía confirmar=true al backend.
  if (_reCreatePlsql.hasMatch(stripped)) return SqlStatementKind.ddl;

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
///
/// Nota: En un `PACKAGE` o `PACKAGE BODY`, la declaración del paquete abre
/// un bloque de nivel superior que concluye con su propio `END [nombre];`.
final _reBlockOpen = RegExp(
  r'\b(PACKAGE(\s+BODY)?|BEGIN|CASE|LOOP)\b|\bIF\b(?!\s*\().*?\bTHEN\b',
  caseSensitive: false,
);
final _reBlockClose = RegExp(r'\bEND\b', caseSensitive: false);

/// Separa un script en sentencias individuales.
///
/// Reglas:
/// - `;` cierra una sentencia sólo si no estamos dentro de un bloque PL/SQL
///   (se cuenta el anidamiento de `BEGIN/CASE/IF…THEN` vs `END`).
/// - En sentencias de creación de objetos (`CREATE [OR REPLACE] ... PROCEDURE/FUNCTION/PACKAGE...`),
///   los `;` de la sección declarativa (antes de `BEGIN` o de abrir bloques) no cortan la sentencia;
///   la sentencia sólo concluye cuando se alcanza el cierre del cuerpo (`END;`) o un terminador `/`.
/// - Una línea que contiene únicamente `/` (convención SQL*Plus) cierra la
///   sentencia PL/SQL o DDL anterior sin necesitar `;`.
/// - Comentarios y literales de texto (incluso `q'[...]'`) no cuentan `;`.
List<SqlStatement> splitStatements(String script) {
  final stripped = stripPlSqlNoise(script);
  final statements = <SqlStatement>[];
  var start = 0;
  var depth = 0;
  var inCreateObject = false;
  var objectHasSeenBlock = false;

  // Precalculamos las posiciones de fin de línea en una única pasada O(N).
  // Esto evita la complejidad cuadrática O(N^2) que provocaba `substring(0, offset)`
  // repetido en scripts con miles de líneas.
  final lineBreakOffsets = <int>[];
  for (var k = 0; k < script.length; k++) {
    if (script.codeUnitAt(k) == 0x0A) {
      lineBreakOffsets.add(k);
    }
  }

  int lineAt(int offset) {
    if (lineBreakOffsets.isEmpty || offset <= lineBreakOffsets[0]) return 0;
    var low = 0;
    var high = lineBreakOffsets.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lineBreakOffsets[mid] < offset) {
        result = mid + 1;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

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
    depth = 0;
    inCreateObject = false;
    objectHasSeenBlock = false;
  }

  var i = 0;
  final n = stripped.length;
  while (i < n) {
    // Si estamos al inicio de una nueva sentencia (o tras whitespace), detectamos
    // si inicia la creación de un objeto PL/SQL almacenado.
    if (!inCreateObject && depth == 0) {
      final currentSlice = stripped.substring(start, i).trim();
      if (currentSlice.isEmpty) {
        final openMatch = _reCreatePlsql.matchAsPrefix(stripped, i);
        if (openMatch != null) {
          inCreateObject = true;
          objectHasSeenBlock = false;
        }
      }
    }

    // Terminador SQL*Plus: línea que sólo contiene "/".
    if ((i == 0 || stripped[i - 1] == '\n') && stripped[i] == '/') {
      final eol = stripped.indexOf('\n', i + 1);
      final restOfLine =
          (eol == -1
                  ? stripped.substring(i + 1)
                  : stripped.substring(i + 1, eol))
              .trim();
      if (restOfLine.isEmpty) {
        // Cierra cualquier sentencia pendiente (haya o no terminado ya en
        // ';'); si no queda nada pendiente, flush() es un no-op seguro.
        flush(i);
        start = i + 1;
        i++;
        continue;
      }
    }

    final openMatch = _reBlockOpen.matchAsPrefix(stripped, i);
    if (openMatch != null) {
      depth++;
      if (inCreateObject) {
        objectHasSeenBlock = true;
      }
      i = openMatch.end;
      continue;
    }
    final closeMatch = _reBlockClose.matchAsPrefix(stripped, i);
    if (closeMatch != null) {
      if (depth > 0) {
        depth--;
      } else if (inCreateObject) {
        // Caso de especificación de PACKAGE o TYPE que no tiene BEGIN pero cierra con `END [nombre];`
        objectHasSeenBlock = true;
      }
      i = closeMatch.end;
      continue;
    }

    if (stripped[i] == ';') {
      if (!inCreateObject && depth == 0) {
        flush(i + 1);
        i++;
        continue;
      } else if (inCreateObject && depth == 0 && objectHasSeenBlock) {
        // En creación de objetos PL/SQL, solo cierra si ya se vio el bloque y depth retornó a 0.
        flush(i + 1);
        i++;
        continue;
      }
    }
    i++;
  }
  flush(n);
  return statements;
}

/// Sentencia bajo el cursor (o que contiene el rango `[selStart, selEnd]`).
SqlStatement? statementAtCursor(String script, int offset) {
  final statements = splitStatements(script);
  if (statements.isEmpty) return null;

  var low = 0;
  var high = statements.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final s = statements[mid];
    if (offset < s.startOffset) {
      high = mid - 1;
    } else if (offset > s.endOffset) {
      low = mid + 1;
    } else {
      return s;
    }
  }
  return statements.last;
}

final _reDdlObjectName = RegExp(
  r'^\s*CREATE\s+(?:OR\s+REPLACE\s+)?'
  r'(?:(?:NOFORCE|FORCE|EDITIONABLE|NONEDITIONABLE)\s+)*'
  r'(PROCEDURE|FUNCTION|PACKAGE(?:\s+BODY)?|TRIGGER|TYPE(?:\s+BODY)?|TABLE|VIEW|INDEX|SEQUENCE|SYNONYM)\s+'
  r'(?:("?[A-Za-z0-9_#$]+"?)?\s*\.\s*)?("?[A-Za-z0-9_#$]+"?)\b',
  caseSensitive: false,
);

/// Extrae metadatos de tipo y nombre del objeto si la sentencia es DDL de creación.
({String? objectType, String? objectName}) extractDdlTarget(String statement) {
  final stripped = stripPlSqlNoise(statement).trim();
  final m = _reDdlObjectName.firstMatch(stripped);
  if (m == null) return (objectType: null, objectName: null);

  final type = m.group(1)?.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  var name = m.group(3)?.replaceAll('"', '');
  return (objectType: type, objectName: name);
}

/// Quita los puntos y coma (`;`) terminales de sentencias SQL (SELECT, DML,
/// EXPLAIN PLAN, COMMAND) que no deben enviarse a Oracle con delimitador final.
///
/// Si la sentencia contiene comentarios al final (por ejemplo `-- comentario` o `/* ... */`),
/// busca hacia atrás el último punto y coma ignorando espacios y comentarios.
/// Bloques PL/SQL no deben pasar por esta función porque requieren sus `;` de cierre.
/// Quita los puntos y coma (`;`) terminales de sentencias SQL (SELECT, DML,
/// EXPLAIN PLAN, COMMAND) que no deben enviarse a Oracle con delimitador final.
///
/// Si la sentencia contiene comentarios al final (por ejemplo `-- comentario` o `/* ... */`),
/// busca hacia atrás el último punto y coma ignorando espacios y comentarios.
/// Bloques PL/SQL no deben pasar por esta función porque requieren sus `;` de cierre.
String stripTrailingSemicolon(String sql) {
  var s = sql.trimRight();
  while (s.endsWith(';')) {
    s = s.substring(0, s.length - 1).trimRight();
  }
  return s;
}

/// Limpia comentarios iniciales huérfanos antes del primer token ejecutable,
/// y remueve el punto y coma final para sentencias SQL puras (SELECT, DML).
///
/// Conserva comentarios internos (hints, notas en WHERE o SELECT) y saltos de línea.
String cleanSqlForExecution(String sql) {
  return stripTrailingSemicolon(sql).trim();
}

/// Extrae las variables de entrada (bind variables) de una sentencia SQL o bloque PL/SQL,
/// tales como `:id`, `:variable`, `:gen.variable`, `:p_dato`.
///
/// Ignora comentarios de línea (`--`), comentarios de bloque (`/* */`) y literales de cadena (`'...'`),
/// así como operadores de asignación PL/SQL (`:=`) y dobles dos puntos (`::`).
/// Devuelve los nombres de las variables sin el prefijo `:` en orden de aparición sin duplicados.
List<String> extractBindVariables(String sql) {
  final stripped = stripPlSqlNoise(sql);
  final binds = <String>[];
  final seen = <String>{};

  var i = 0;
  final n = stripped.length;
  while (i < n) {
    final c = stripped[i];

    // Detectar ':'
    if (c == ':') {
      // Ignorar asignación ':=' o '::'
      if (i + 1 < n && (stripped[i + 1] == '=' || stripped[i + 1] == ':')) {
        i += 2;
        continue;
      }

      // Debe comenzar con carácter alfanumérico o guión bajo
      if (i + 1 < n && _isBindWordChar(stripped[i + 1])) {
        var j = i + 1;
        while (j < n) {
          if (_isBindWordChar(stripped[j])) {
            j++;
          } else if (stripped[j] == '.' && j + 1 < n && _isBindWordChar(stripped[j + 1])) {
            j++; // Notación de punto: :gen.variable
          } else {
            break;
          }
        }

        final varName = stripped.substring(i + 1, j);
        final varKey = varName.toUpperCase();
        // Ignorar pseudo-variables de triggers si aplican (:NEW y :OLD sin campo son raras, pero si es :NEW.COL o :OLD.COL
        // en triggers se excluyen si el usuario lo desea, aunque en queries de prueba pueden ser variables legítimas)
        if (!seen.contains(varKey)) {
          seen.add(varKey);
          binds.add(varName);
        }
        i = j;
        continue;
      }
    }
    i++;
  }

  return binds;
}

bool _isBindWordChar(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) || // A-Z
      (code >= 0x61 && code <= 0x7A) || // a-z
      (code >= 0x30 && code <= 0x39) || // 0-9
      code == 0x5F || // _
      code == 0x24 || // $
      code == 0x23; // #
}
