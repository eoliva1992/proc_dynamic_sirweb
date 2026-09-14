import 'package:flutter/painting.dart';

/// Resaltado de sintaxis para los bloques de código del chat.
///
/// Es un tokenizador **léxico** deliberadamente simple —sin gramática ni
/// AST— porque solo tiene que colorear un fragmento de respuesta, no
/// compilarlo. Se implementa a mano en vez de añadir una dependencia porque
/// el subconjunto necesario (PL/SQL y «lo demás») es pequeño y así el
/// resultado se puede probar sin levantar un widget.

/// Categoría léxica de un fragmento de código.
enum CodeTokenKind {
  plain,
  keyword,
  type,
  function,
  string,
  comment,
  number,
  param,
}

/// Un fragmento de código ya clasificado.
class CodeToken {
  final String text;
  final CodeTokenKind kind;

  const CodeToken(this.text, this.kind);

  @override
  String toString() => '${kind.name}(${text.replaceAll('\n', r'\n')})';

  @override
  bool operator ==(Object other) =>
      other is CodeToken && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);
}

/// Paleta tomada de los temas **Dark+** y **Light+** de VS Code.
///
/// Un bloque de código del chat debe leerse igual que el mismo código en el
/// editor; con texto monocromo el ojo pierde la referencia al saltar de uno
/// a otro.
class SyntaxPalette {
  final Color plain;
  final Color keyword;
  final Color type;
  final Color function;
  final Color string;
  final Color comment;
  final Color number;
  final Color param;

  const SyntaxPalette({
    required this.plain,
    required this.keyword,
    required this.type,
    required this.function,
    required this.string,
    required this.comment,
    required this.number,
    required this.param,
  });

  static const dark = SyntaxPalette(
    plain: Color(0xFFD4D4D4),
    keyword: Color(0xFF569CD6),
    type: Color(0xFF4EC9B0),
    function: Color(0xFFDCDCAA),
    string: Color(0xFFCE9178),
    comment: Color(0xFF6A9955),
    number: Color(0xFFB5CEA8),
    param: Color(0xFF9CDCFE),
  );

  static const light = SyntaxPalette(
    plain: Color(0xFF1F1F1F),
    keyword: Color(0xFF0000FF),
    type: Color(0xFF267F99),
    function: Color(0xFF795E26),
    string: Color(0xFFA31515),
    comment: Color(0xFF008000),
    number: Color(0xFF098658),
    param: Color(0xFF001080),
  );

  Color of(CodeTokenKind kind) => switch (kind) {
    CodeTokenKind.plain => plain,
    CodeTokenKind.keyword => keyword,
    CodeTokenKind.type => type,
    CodeTokenKind.function => function,
    CodeTokenKind.string => string,
    CodeTokenKind.comment => comment,
    CodeTokenKind.number => number,
    CodeTokenKind.param => param,
  };
}

/// Lenguajes que se resaltan con las reglas de PL/SQL.
///
/// Un bloque **sin lenguaje** también entra aquí: en este editor casi todo el
/// código que devuelve Copilot es PL/SQL, así que acertar por defecto vale
/// más que ser neutral.
const kSqlLanguages = {
  '',
  'sql',
  'plsql',
  'pl/sql',
  'pl-sql',
  'oracle',
  'oraclesql',
  'plpgsql',
};

const _kSqlKeywords = {
  'ACCESS',
  'ADD',
  'ALL',
  'ALTER',
  'AND',
  'ANY',
  'AS',
  'ASC',
  'AT',
  'AUTHID',
  'BEGIN',
  'BETWEEN',
  'BODY',
  'BULK',
  'BY',
  'CASE',
  'CLOSE',
  'COLLECT',
  'COMMENT',
  'COMMIT',
  'CONNECT',
  'CONSTANT',
  'CONTINUE',
  'CREATE',
  'CROSS',
  'CURRENT',
  'CURSOR',
  'DECLARE',
  'DEFAULT',
  'DELETE',
  'DESC',
  'DETERMINISTIC',
  'DISTINCT',
  'DROP',
  'EACH',
  'ELSE',
  'ELSIF',
  'END',
  'EXCEPTION',
  'EXECUTE',
  'EXISTS',
  'EXIT',
  'FETCH',
  'FOR',
  'FORALL',
  'FROM',
  'FULL',
  'FUNCTION',
  'GOTO',
  'GRANT',
  'GROUP',
  'HAVING',
  'IF',
  'IMMEDIATE',
  'IN',
  'INDEX',
  'INNER',
  'INSERT',
  'INTERSECT',
  'INTO',
  'IS',
  'JOIN',
  'KEY',
  'LEFT',
  'LEVEL',
  'LIKE',
  'LOOP',
  'MERGE',
  'MINUS',
  'NOCOPY',
  'NOT',
  'NULL',
  'NULLS',
  'OF',
  'ON',
  'OPEN',
  'OR',
  'ORDER',
  'OTHERS',
  'OUT',
  'OUTER',
  'OVER',
  'PACKAGE',
  'PARTITION',
  'PIPELINED',
  'PRAGMA',
  'PRIOR',
  'PROCEDURE',
  'RAISE',
  'REPLACE',
  'RETURN',
  'RETURNING',
  'REVERSE',
  'RIGHT',
  'ROLLBACK',
  'ROW',
  'ROWTYPE',
  'SAVEPOINT',
  'SELECT',
  'SET',
  'START',
  'SUBTYPE',
  'THEN',
  'TRIGGER',
  'TYPE',
  'UNION',
  'UNIQUE',
  'UPDATE',
  'USING',
  'VALUES',
  'VIEW',
  'WHEN',
  'WHERE',
  'WHILE',
  'WITH',
  'TRUE',
  'FALSE',
};

const _kSqlTypes = {
  'BFILE',
  'BINARY_INTEGER',
  'BLOB',
  'BOOLEAN',
  'CHAR',
  'CLOB',
  'DATE',
  'DECIMAL',
  'DOUBLE',
  'FLOAT',
  'INTEGER',
  'INTERVAL',
  'LONG',
  'NCHAR',
  'NCLOB',
  'NUMBER',
  'NUMERIC',
  'NVARCHAR2',
  'PLS_INTEGER',
  'RAW',
  'RECORD',
  'REF',
  'ROWID',
  'SIMPLE_INTEGER',
  'SMALLINT',
  'TABLE',
  'TIMESTAMP',
  'VARCHAR',
  'VARCHAR2',
  'VARRAY',
  'XMLTYPE',
};

const _kSqlFunctions = {
  'ABS',
  'ADD_MONTHS',
  'AVG',
  'CAST',
  'CEIL',
  'COALESCE',
  'CONCAT',
  'COUNT',
  'DECODE',
  'EXTRACT',
  'FLOOR',
  'GREATEST',
  'INSTR',
  'LAST_DAY',
  'LEAST',
  'LENGTH',
  'LOWER',
  'LPAD',
  'LTRIM',
  'MAX',
  'MIN',
  'MOD',
  'MONTHS_BETWEEN',
  'NVL',
  'NVL2',
  'RAISE_APPLICATION_ERROR',
  'REGEXP_LIKE',
  'REGEXP_REPLACE',
  'REGEXP_SUBSTR',
  'ROUND',
  'ROW_NUMBER',
  'RPAD',
  'RTRIM',
  'SUBSTR',
  'SUM',
  'SYSDATE',
  'SYSTIMESTAMP',
  'TO_CHAR',
  'TO_DATE',
  'TO_NUMBER',
  'TRIM',
  'TRUNC',
  'UPPER',
  'USER',
};

/// Palabras reservadas frecuentes en los demás lenguajes que puede devolver
/// Copilot (Dart, JS, Python, C#…). Una sola lista basta para el contraste.
const _kGenericKeywords = {
  'abstract',
  'as',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'def',
  'default',
  'do',
  'elif',
  'else',
  'enum',
  'export',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'from',
  'function',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'let',
  'new',
  'null',
  'operator',
  'package',
  'private',
  'protected',
  'public',
  'return',
  'static',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

final _wordChar = RegExp(r'[A-Za-z0-9_$#]');
final _letter = RegExp('[A-Za-z]');

bool _isWordChar(String c) => _wordChar.hasMatch(c);

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

/// Trocea [code] según el [language] indicado en el fence del markdown.
List<CodeToken> tokenizeCode(String code, String? language) {
  final lang = (language ?? '').toLowerCase().trim();
  return kSqlLanguages.contains(lang)
      ? _tokenizeSql(code)
      : _tokenizeGeneric(code);
}

/// Convierte [code] en `TextSpan` listos para un `RichText`.
List<TextSpan> highlightCode(
  String code,
  String? language, {
  required bool isDark,
}) {
  final palette = isDark ? SyntaxPalette.dark : SyntaxPalette.light;
  return [
    for (final t in tokenizeCode(code, language))
      TextSpan(
        text: t.text,
        style: TextStyle(
          color: palette.of(t.kind),
          fontStyle: t.kind == CodeTokenKind.comment ? FontStyle.italic : null,
        ),
      ),
  ];
}

/// Acumulador que fusiona los fragmentos `plain` consecutivos.
///
/// Sin esto, un `SELECT a, b` generaría un `TextSpan` por coma y por espacio.
class _Sink {
  final List<CodeToken> tokens = [];
  final StringBuffer _plain = StringBuffer();

  void plain(String text) => _plain.write(text);

  void emit(String text, CodeTokenKind kind) {
    flush();
    tokens.add(CodeToken(text, kind));
  }

  void flush() {
    if (_plain.isEmpty) return;
    tokens.add(CodeToken(_plain.toString(), CodeTokenKind.plain));
    _plain.clear();
  }
}

List<CodeToken> _tokenizeSql(String s) {
  final out = _Sink();
  var i = 0;

  while (i < s.length) {
    final ch = s[i];

    // Comentario de línea `-- …`
    if (ch == '-' && i + 1 < s.length && s[i + 1] == '-') {
      final nl = s.indexOf('\n', i);
      final stop = nl == -1 ? s.length : nl;
      out.emit(s.substring(i, stop), CodeTokenKind.comment);
      i = stop;
      continue;
    }

    // Comentario de bloque; puede quedar sin cerrar si el streaming lo cortó.
    if (ch == '/' && i + 1 < s.length && s[i + 1] == '*') {
      final end = s.indexOf('*/', i + 2);
      final stop = end == -1 ? s.length : end + 2;
      out.emit(s.substring(i, stop), CodeTokenKind.comment);
      i = stop;
      continue;
    }

    // Literal de texto; en Oracle la comilla se escapa duplicándola.
    if (ch == "'") {
      var j = i + 1;
      while (j < s.length) {
        if (s[j] == "'") {
          if (j + 1 < s.length && s[j + 1] == "'") {
            j += 2;
            continue;
          }
          j++;
          break;
        }
        j++;
      }
      out.emit(s.substring(i, j), CodeTokenKind.string);
      i = j;
      continue;
    }

    // Identificador entre comillas dobles.
    if (ch == '"') {
      final end = s.indexOf('"', i + 1);
      final stop = end == -1 ? s.length : end + 1;
      out.emit(s.substring(i, stop), CodeTokenKind.type);
      i = stop;
      continue;
    }

    // Bind variable `:p_dato`, omnipresente en las reglas dinámicas.
    if (ch == ':' && i + 1 < s.length && _isWordChar(s[i + 1])) {
      var j = i + 1;
      while (j < s.length && _isWordChar(s[j])) {
        j++;
      }
      out.emit(s.substring(i, j), CodeTokenKind.param);
      i = j;
      continue;
    }

    if (_isDigit(ch)) {
      var j = i;
      while (j < s.length && (_isDigit(s[j]) || s[j] == '.')) {
        j++;
      }
      out.emit(s.substring(i, j), CodeTokenKind.number);
      i = j;
      continue;
    }

    if (_isWordChar(ch)) {
      var j = i;
      while (j < s.length && _isWordChar(s[j])) {
        j++;
      }
      final word = s.substring(i, j);
      final upper = word.toUpperCase();

      if (_kSqlKeywords.contains(upper)) {
        out.emit(word, CodeTokenKind.keyword);
      } else if (_kSqlTypes.contains(upper)) {
        out.emit(word, CodeTokenKind.type);
      } else if (_kSqlFunctions.contains(upper) || _isCall(s, j)) {
        // Lo que va seguido de `(` se pinta como llamada aunque no esté en la
        // lista: así los paquetes del propio esquema también se distinguen.
        out.emit(word, CodeTokenKind.function);
      } else {
        out.plain(word);
      }
      i = j;
      continue;
    }

    out.plain(ch);
    i++;
  }

  out.flush();
  return out.tokens;
}

List<CodeToken> _tokenizeGeneric(String s) {
  final out = _Sink();
  var i = 0;

  while (i < s.length) {
    final ch = s[i];

    if ((ch == '/' && i + 1 < s.length && s[i + 1] == '/') || ch == '#') {
      final nl = s.indexOf('\n', i);
      final stop = nl == -1 ? s.length : nl;
      out.emit(s.substring(i, stop), CodeTokenKind.comment);
      i = stop;
      continue;
    }

    if (ch == '/' && i + 1 < s.length && s[i + 1] == '*') {
      final end = s.indexOf('*/', i + 2);
      final stop = end == -1 ? s.length : end + 2;
      out.emit(s.substring(i, stop), CodeTokenKind.comment);
      i = stop;
      continue;
    }

    if (ch == '"' || ch == "'" || ch == '`') {
      var j = i + 1;
      while (j < s.length) {
        if (s[j] == r'\') {
          j += 2;
          continue;
        }
        if (s[j] == ch) {
          j++;
          break;
        }
        // Una cadena sin cerrar no se come el resto del fichero.
        if (s[j] == '\n') break;
        j++;
      }
      out.emit(s.substring(i, j), CodeTokenKind.string);
      i = j;
      continue;
    }

    if (_isDigit(ch)) {
      var j = i;
      while (j < s.length && (_isDigit(s[j]) || s[j] == '.')) {
        j++;
      }
      out.emit(s.substring(i, j), CodeTokenKind.number);
      i = j;
      continue;
    }

    if (_isWordChar(ch)) {
      var j = i;
      while (j < s.length && _isWordChar(s[j])) {
        j++;
      }
      final word = s.substring(i, j);

      if (_kGenericKeywords.contains(word)) {
        out.emit(word, CodeTokenKind.keyword);
      } else if (_letter.hasMatch(word[0]) &&
          word[0] == word[0].toUpperCase()) {
        // Convención casi universal: los tipos van en CamelCase.
        out.emit(word, CodeTokenKind.type);
      } else if (_isCall(s, j)) {
        out.emit(word, CodeTokenKind.function);
      } else {
        out.plain(word);
      }
      i = j;
      continue;
    }

    out.plain(ch);
    i++;
  }

  out.flush();
  return out.tokens;
}

/// ¿La palabra que acaba en [from] va seguida de un paréntesis de llamada?
bool _isCall(String s, int from) {
  var k = from;
  while (k < s.length && s[k] == ' ') {
    k++;
  }
  return k < s.length && s[k] == '(';
}
