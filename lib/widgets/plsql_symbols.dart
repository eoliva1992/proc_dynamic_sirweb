// ── Símbolos PL/SQL declarados en el fuente ──────────────────────────────────
//
// Extrae parámetros, variables, constantes, cursores, excepciones, tipos y
// subprogramas del código fuente de un objeto Oracle para alimentar el
// autocompletado del editor.
//
// Es un parser léxico (no un parser completo de PL/SQL): trabaja sobre el texto
// ya limpio de comentarios y literales, por lo que es tolerante a código
// incompleto o con errores de sintaxis mientras se escribe.

/// Tipo de símbolo declarado en el fuente.
enum PlSqlSymbolKind {
  parameter,
  variable,
  constant,
  cursor,
  exception,
  type,
  subprogram,
}

/// Un identificador declarado en el fuente PL/SQL.
class PlSqlSymbol {
  const PlSqlSymbol({
    required this.name,
    required this.kind,
    this.dataType,
    this.scope,
    this.line = 0,
  });

  /// Nombre del identificador tal como fue declarado.
  final String name;

  final PlSqlSymbolKind kind;

  /// Tipo de dato declarado (`VARCHAR2`, `tabla.columna%TYPE`…), si se pudo
  /// determinar.
  final String? dataType;

  /// Subprograma que lo contiene (`null` = ámbito global del paquete/bloque).
  final String? scope;

  final int line;

  /// Texto secundario para mostrar en la lista de autocompletado.
  String get detail {
    final tipo = switch (kind) {
      PlSqlSymbolKind.parameter => 'parámetro',
      PlSqlSymbolKind.variable => 'variable',
      PlSqlSymbolKind.constant => 'constante',
      PlSqlSymbolKind.cursor => 'cursor',
      PlSqlSymbolKind.exception => 'excepción',
      PlSqlSymbolKind.type => 'tipo',
      PlSqlSymbolKind.subprogram => 'subprograma',
    };
    final buf = StringBuffer(tipo);
    if (dataType != null && dataType!.isNotEmpty) buf.write(' · $dataType');
    if (scope != null && scope!.isNotEmpty) buf.write('  ($scope)');
    return buf.toString();
  }

  @override
  String toString() => '$name [$kind]';
}

// ── Limpieza previa ──────────────────────────────────────────────────────────

/// Reemplaza comentarios y literales de texto por espacios, preservando los
/// saltos de línea para que los números de línea sigan siendo válidos.
String stripPlSqlNoise(String code) {
  final out = StringBuffer();
  var i = 0;
  final n = code.length;
  while (i < n) {
    final c = code[i];
    final next = i + 1 < n ? code[i + 1] : '';

    // Comentario de línea
    if (c == '-' && next == '-') {
      while (i < n && code[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    // Comentario de bloque
    if (c == '/' && next == '*') {
      while (i < n && !(code[i] == '*' && i + 1 < n && code[i + 1] == '/')) {
        out.write(code[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < n) {
        out.write('  ');
        i += 2;
      }
      continue;
    }
    // Literal de texto
    if (c == "'") {
      out.write(' ');
      i++;
      while (i < n) {
        if (code[i] == "'") {
          // '' escapado dentro del literal
          if (i + 1 < n && code[i + 1] == "'") {
            out.write('  ');
            i += 2;
            continue;
          }
          out.write(' ');
          i++;
          break;
        }
        out.write(code[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

// ── Expresiones ──────────────────────────────────────────────────────────────

// Nombre del subprograma. Oracle devuelve el fuente con el nombre calificado y
// entrecomillado (`PROCEDURE "SIR"."PR_X"`), o simple (`PROCEDURE pr_x`): se
// admite el esquema opcional y se captura siempre el identificador final.
final _reSubprogram = RegExp(
  r'\b(PROCEDURE|FUNCTION)\s+'
  r'(?:"?[A-Za-z_][\w$#]*"?\s*\.\s*)?'
  r'"?([A-Za-z_][\w$#]*)"?',
  caseSensitive: false,
);
final _reDeclareKw = RegExp(r'^\s*DECLARE\b', caseSensitive: false);
final _reBeginKw = RegExp(r'^\s*BEGIN\b', caseSensitive: false);
final _reEndsWithIsAs = RegExp(r'\b(IS|AS)\s*$', caseSensitive: false);
final _reCursorDecl = RegExp(r'^CURSOR\s+([A-Za-z_]\w*)', caseSensitive: false);
final _reExceptionDecl = RegExp(
  r'^([A-Za-z_]\w*)\s+EXCEPTION$',
  caseSensitive: false,
);
final _reTypeDecl = RegExp(
  r'^(?:TYPE|SUBTYPE)\s+([A-Za-z_]\w*)',
  caseSensitive: false,
);
final _reVarDecl = RegExp(
  r'^([A-Za-z_]\w*)\s+(CONSTANT\s+)?([^:]+?)\s*(?::=|DEFAULT\b|$)',
  caseSensitive: false,
);

/// Palabras reservadas que nunca son nombres de variables.
const _kReserved = {
  'BEGIN',
  'END',
  'IF',
  'THEN',
  'ELSE',
  'ELSIF',
  'FOR',
  'LOOP',
  'WHILE',
  'DECLARE',
  'EXCEPTION',
  'WHEN',
  'CURSOR',
  'RETURN',
  'PROCEDURE',
  'FUNCTION',
  'TYPE',
  'SUBTYPE',
  'PRAGMA',
  'SELECT',
  'UPDATE',
  'DELETE',
  'INSERT',
  'INTO',
  'FROM',
  'WHERE',
  'NULL',
  'RAISE',
  'COMMIT',
  'ROLLBACK',
  'AND',
  'OR',
  'NOT',
  'IN',
  'OUT',
  'IS',
  'AS',
  'CREATE',
  'REPLACE',
  'PACKAGE',
  'BODY',
  'GRANT',
  'OR REPLACE',
  'END IF',
  'END LOOP',
  'OPEN',
  'CLOSE',
  'FETCH',
  'EXIT',
  'GOTO',
  'CASE',
  'MERGE',
  'SET',
  'VALUES',
  'USING',
  'ON',
  'ORDER',
  'GROUP',
  'HAVING',
  'UNION',
  'MINUS',
  'INTERSECT',
  'EXECUTE',
  'IMMEDIATE',
  'FORALL',
};

/// Extrae los parámetros de la lista `(...)` que comienza en [open].
///
/// Devuelve los símbolos y el índice del paréntesis de cierre.
({List<PlSqlSymbol> params, int close}) _parseParams(
  String src,
  int open,
  String scope,
  List<int> lineStarts,
) {
  final params = <PlSqlSymbol>[];
  var depth = 0;
  var i = open;
  final segStart = <int>[];
  var current = StringBuffer();
  var currentStart = open + 1;

  void flush(int end) {
    final text = current.toString().trim();
    current = StringBuffer();
    if (text.isEmpty) return;
    // nombre [IN [OUT] | OUT] tipo [:= | DEFAULT valor]
    final m = RegExp(
      r'^([A-Za-z_]\w*)\s+(?:(IN\s+OUT|IN|OUT)\s+)?(.*)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (m == null) return;
    final name = m.group(1)!;
    if (_kReserved.contains(name.toUpperCase())) return;
    var tipo = (m.group(3) ?? '').trim();
    final defIdx = tipo.indexOf(':=');
    if (defIdx >= 0) tipo = tipo.substring(0, defIdx).trim();
    final defKw = RegExp(r'\bDEFAULT\b', caseSensitive: false).firstMatch(tipo);
    if (defKw != null) tipo = tipo.substring(0, defKw.start).trim();
    final modo = m.group(2)?.toUpperCase();
    params.add(
      PlSqlSymbol(
        name: name,
        kind: PlSqlSymbolKind.parameter,
        dataType: [?modo, if (tipo.isNotEmpty) tipo].join(' ').trim(),
        scope: scope,
        line: _lineOf(currentStart, lineStarts),
      ),
    );
  }

  while (i < src.length) {
    final c = src[i];
    if (c == '(') {
      depth++;
      if (depth == 1) {
        currentStart = i + 1;
        i++;
        continue;
      }
    } else if (c == ')') {
      depth--;
      if (depth == 0) {
        flush(i);
        return (params: params, close: i);
      }
    } else if (c == ',' && depth == 1) {
      flush(i);
      currentStart = i + 1;
      i++;
      continue;
    }
    if (depth >= 1) current.write(c);
    i++;
  }
  flush(src.length);
  segStart.clear();
  return (params: params, close: src.length);
}

int _lineOf(int offset, List<int> lineStarts) {
  var lo = 0, hi = lineStarts.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lineStarts[mid] <= offset) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return lo; // 1-based
}

/// Analiza [code] y devuelve los identificadores declarados.
///
/// Pensado para usarse con `compute()` — es una función top-level pura.
List<PlSqlSymbol> parsePlSqlSymbols(String code) {
  if (code.trim().isEmpty) return const [];
  final src = stripPlSqlNoise(code);

  final lineStarts = <int>[0];
  for (var i = 0; i < src.length; i++) {
    if (src[i] == '\n') lineStarts.add(i + 1);
  }

  final out = <PlSqlSymbol>[];
  final seen = <String>{};
  void add(PlSqlSymbol s) {
    if (s.name.isEmpty) return;
    if (_kReserved.contains(s.name.toUpperCase())) return;
    // Un mismo nombre puede repetirse en distintos subprogramas: se conserva
    // la primera aparición para no saturar la lista de sugerencias.
    if (!seen.add('${s.kind.name}:${s.name.toUpperCase()}')) return;
    out.add(s);
  }

  // ── 1. Subprogramas y sus parámetros ──────────────────────────────────────
  for (final m in _reSubprogram.allMatches(src)) {
    final name = m.group(2)!;
    add(
      PlSqlSymbol(
        name: name,
        kind: PlSqlSymbolKind.subprogram,
        dataType: m.group(1)!.toUpperCase(),
        line: _lineOf(m.start, lineStarts),
      ),
    );
    // Buscar el '(' de la lista de parámetros justo después del nombre.
    var j = m.end;
    while (j < src.length &&
        (src[j] == ' ' || src[j] == '\n' || src[j] == '\r' || src[j] == '\t')) {
      j++;
    }
    if (j < src.length && src[j] == '(') {
      final res = _parseParams(src, j, name, lineStarts);
      res.params.forEach(add);
    }
  }

  // ── 2. Declaraciones (variables, constantes, cursores, excepciones…) ──────
  // Se recorre línea a línea manteniendo si estamos en una sección declarativa
  // (entre IS/AS o DECLARE y el BEGIN correspondiente).
  final lines = src.split('\n');
  var inDeclare = false;
  var scope = <String>[];
  final buf = StringBuffer();
  var bufLine = 1;

  void flushBuffer() {
    final acc = buf.toString();
    buf.clear();
    for (final seg in acc.split(';')) {
      final t = seg.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isEmpty) continue;

      final cur = _reCursorDecl.firstMatch(t);
      if (cur != null) {
        add(
          PlSqlSymbol(
            name: cur.group(1)!,
            kind: PlSqlSymbolKind.cursor,
            scope: scope.isEmpty ? null : scope.last,
            line: bufLine,
          ),
        );
        continue;
      }
      final exc = _reExceptionDecl.firstMatch(t);
      if (exc != null) {
        add(
          PlSqlSymbol(
            name: exc.group(1)!,
            kind: PlSqlSymbolKind.exception,
            scope: scope.isEmpty ? null : scope.last,
            line: bufLine,
          ),
        );
        continue;
      }
      final tp = _reTypeDecl.firstMatch(t);
      if (tp != null) {
        add(
          PlSqlSymbol(
            name: tp.group(1)!,
            kind: PlSqlSymbolKind.type,
            scope: scope.isEmpty ? null : scope.last,
            line: bufLine,
          ),
        );
        continue;
      }
      // Las firmas de subprogramas ya se procesaron en el paso 1.
      if (RegExp(
        r'^(PROCEDURE|FUNCTION|PRAGMA|BEGIN|END)\b',
        caseSensitive: false,
      ).hasMatch(t)) {
        continue;
      }
      final v = _reVarDecl.firstMatch(t);
      if (v != null) {
        final tipo = (v.group(3) ?? '').trim();
        // Una declaración siempre tiene tipo; si no, es una sentencia suelta.
        if (tipo.isEmpty) continue;
        add(
          PlSqlSymbol(
            name: v.group(1)!,
            kind: v.group(2) != null
                ? PlSqlSymbolKind.constant
                : PlSqlSymbolKind.variable,
            dataType: tipo,
            scope: scope.isEmpty ? null : scope.last,
            line: bufLine,
          ),
        );
      }
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    final sub = _reSubprogram.firstMatch(raw);
    if (sub != null) {
      flushBuffer();
      scope = [sub.group(2)!];
      // Header terminado en IS/AS → arranca su sección declarativa.
      inDeclare = _reEndsWithIsAs.hasMatch(raw);
      bufLine = i + 1;
      continue;
    }
    if (_reDeclareKw.hasMatch(raw)) {
      flushBuffer();
      inDeclare = true;
      bufLine = i + 1;
      continue;
    }
    if (_reBeginKw.hasMatch(raw)) {
      flushBuffer();
      inDeclare = false;
      continue;
    }
    // `) IS`, `IS`, `AS` … cierran la firma y abren la sección declarativa.
    if (_reEndsWithIsAs.hasMatch(raw)) {
      flushBuffer();
      inDeclare = true;
      bufLine = i + 1;
      continue;
    }
    if (!inDeclare) continue;

    if (buf.isEmpty) bufLine = i + 1;
    buf.write(' ');
    buf.write(raw);
    if (raw.contains(';')) flushBuffer();
  }
  flushBuffer();

  return out;
}
