part of 'code_editor_panel.dart';

// ─── PL/SQL Syntax Checker (Oracle) ────────────────────────────────────────
//
// Valida la estructura sintáctica de código PL/SQL en dos fases:
//
//   1. _PlSqlLexer  – tokeniza la fuente carácter a carácter, omitiendo el
//                     contenido de strings ('…' con escape '') y comentarios
//                     (-- de línea y /* … */ de bloque).
//
//   2. _PlSqlParser – recorre la lista de tokens y detecta:
//                     • Paréntesis sin cerrar / sin abrir  ()
//                     • BEGIN … END
//                     • IF … END IF
//                     • FOR/WHILE/LOOP … END LOOP
//                     • CASE … END CASE  (sentencia)
//                     • CASE … END       (expresión, ej.: v := CASE…END)
//                     • Comentario /* sin cerrar
//                     • Literal de cadena ' sin cerrar
//
// Notas de diseño
// ───────────────
// • CASE siempre empuja el stack. Un END simple (sin IF/LOOP/CASE) cierra
//   BEGIN o CASE indistintamente, cubriendo tanto CASE-sentencia que se cierre
//   mal como CASE-expresión que se cierre con bare END.
// • DECLARE, EXCEPTION, ELSIF, ELSE, THEN, WHEN no modifican el stack.
// • END <label> (ej.: END my_proc;) se trata como END simple.

// ─── Tipos de token ───────────────────────────────────────────────────────────

enum _PlTok {
  begin, //  BEGIN
  end, //    END  (look-ahead necesario: IF / LOOP / CASE / <label> / nada)
  kIf, //    IF   (no ELSIF)
  kElsif, // ELSIF / ELSEIF
  kElse, //  ELSE
  kThen, //  THEN
  kFor, //   FOR
  kWhile, // WHILE
  kLoop, //  LOOP
  kCase, //  CASE
  kWhen, //  WHEN
  kDeclare, //   DECLARE
  kException, // EXCEPTION
  lparen, // (
  rparen, // )
  semi, //   ;
  ident, //  cualquier identificador que no sea keyword
}

class _PlToken {
  final _PlTok type;
  final int line; // 1-based
  final int col; // 1-based
  final String text;

  const _PlToken(this.type, this.line, this.col, this.text);

  @override
  String toString() => '${type.name}(`$text`)@$line:$col';
}

// ─── Lexer ───────────────────────────────────────────────────────────────────

class _PlSqlLexer {
  final String _code;

  _PlSqlLexer(this._code);

  ({List<_PlToken> tokens, List<_SyntaxError> errors}) tokenize() {
    final tokens = <_PlToken>[];
    final errors = <_SyntaxError>[];
    final lines = _code.split('\n');

    bool inString = false;
    int strLine = 0, strCol = 0;

    bool inBlock = false; // dentro de /* … */
    int blkLine = 0, blkCol = 0;

    for (int li = 0; li < lines.length; li++) {
      final src = lines[li];
      int ci = 0;

      while (ci < src.length) {
        // ── Dentro de comentario de bloque ──────────────────────────────────
        if (inBlock) {
          if (ci + 1 < src.length && src[ci] == '*' && src[ci + 1] == '/') {
            inBlock = false;
            ci += 2;
          } else {
            ci++;
          }
          continue;
        }

        // ── Dentro de literal de cadena ──────────────────────────────────────
        if (inString) {
          if (src[ci] == '\'') {
            if (ci + 1 < src.length && src[ci + 1] == '\'') {
              ci += 2; // '' es el escape de ' en PL/SQL
            } else {
              inString = false;
              ci++;
            }
          } else {
            ci++;
          }
          continue;
        }

        // ── Inicio de comentario de bloque ───────────────────────────────────
        if (ci + 1 < src.length && src[ci] == '/' && src[ci + 1] == '*') {
          inBlock = true;
          blkLine = li + 1;
          blkCol = ci + 1;
          ci += 2;
          continue;
        }

        // ── Comentario de línea ──────────────────────────────────────────────
        if (ci + 1 < src.length && src[ci] == '-' && src[ci + 1] == '-') {
          break;
        }

        // ── Inicio de literal de cadena ──────────────────────────────────────
        if (src[ci] == '\'') {
          inString = true;
          strLine = li + 1;
          strCol = ci + 1;
          ci++;
          continue;
        }

        // ── Identificador o keyword ──────────────────────────────────────────
        final c0 = src.codeUnitAt(ci);
        if (_isAlpha(c0)) {
          final start = ci;
          while (ci < src.length && _isAlphaNum(src.codeUnitAt(ci))) {
            ci++;
          }
          _emit(tokens, src.substring(start, ci), li + 1, start + 1);
          continue;
        }

        // ── Símbolos relevantes ──────────────────────────────────────────────
        switch (src[ci]) {
          case '(':
            tokens.add(_PlToken(_PlTok.lparen, li + 1, ci + 1, '('));
          case ')':
            tokens.add(_PlToken(_PlTok.rparen, li + 1, ci + 1, ')'));
          case ';':
            tokens.add(_PlToken(_PlTok.semi, li + 1, ci + 1, ';'));
        }
        ci++;
      }
    }

    if (inBlock) {
      errors.add(
        _SyntaxError(
          line: blkLine,
          col: blkCol,
          message: 'Comentario /* sin cerrar',
        ),
      );
    }
    if (inString) {
      errors.add(
        _SyntaxError(
          line: strLine,
          col: strCol,
          message: "Cadena de texto sin cerrar (falta ')",
        ),
      );
    }

    return (tokens: tokens, errors: errors);
  }

  static void _emit(List<_PlToken> out, String word, int line, int col) {
    final kw = _kw[word.toUpperCase()];
    out.add(_PlToken(kw ?? _PlTok.ident, line, col, word.toUpperCase()));
  }

  static const _kw = <String, _PlTok>{
    'BEGIN': _PlTok.begin,
    'END': _PlTok.end,
    'IF': _PlTok.kIf,
    'ELSIF': _PlTok.kElsif,
    'ELSEIF': _PlTok.kElsif,
    'ELSE': _PlTok.kElse,
    'THEN': _PlTok.kThen,
    'FOR': _PlTok.kFor,
    'WHILE': _PlTok.kWhile,
    'LOOP': _PlTok.kLoop,
    'CASE': _PlTok.kCase,
    'WHEN': _PlTok.kWhen,
    'DECLARE': _PlTok.kDeclare,
    'EXCEPTION': _PlTok.kException,
  };

  static bool _isAlpha(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;

  static bool _isAlphaNum(int c) => _isAlpha(c) || (c >= 48 && c <= 57);
}

// ─── Parser ───────────────────────────────────────────────────────────────────

class _PlSqlParser {
  final List<_PlToken> _toks;
  final List<_SyntaxError> _errs;

  // Stack de bloques: ({línea de apertura, tipo})
  // tipo ∈ { 'BEGIN', 'IF', 'LOOP', 'CASE' }
  final List<({int line, String type})> _blocks = [];

  // Stack de paréntesis sin cerrar
  final List<({int line, int col})> _parens = [];

  int _i = 0;

  _PlSqlParser(this._toks, this._errs);

  List<_SyntaxError> validate() {
    while (_i < _toks.length) {
      _step(_toks[_i]);
      _i++;
    }
    _reportUnclosed();
    _errs.sort((a, b) => a.line.compareTo(b.line));
    return _errs;
  }

  // ── Procesar un token ─────────────────────────────────────────────────────

  void _step(_PlToken t) {
    switch (t.type) {
      // ── Balance de paréntesis ──────────────────────────────────────────────
      case _PlTok.lparen:
        _parens.add((line: t.line, col: t.col));

      case _PlTok.rparen:
        if (_parens.isEmpty) {
          _err(t.line, t.col, ') sin ( correspondiente');
        } else {
          _parens.removeLast();
        }

      // ── Abre bloque ────────────────────────────────────────────────────────
      case _PlTok.begin:
        _blocks.add((line: t.line, type: 'BEGIN'));

      case _PlTok.kIf:
        // IF abre un bloque que cierra con END IF.
        // ELSIF tiene su propio tipo y no abre un nuevo bloque.
        _blocks.add((line: t.line, type: 'IF'));

      case _PlTok.kLoop:
        // LOOP aparece al final de FOR…LOOP, WHILE…LOOP y LOOP simple.
        // En los tres casos abre un bloque que cierra con END LOOP.
        _blocks.add((line: t.line, type: 'LOOP'));

      case _PlTok.kCase:
        // Se empuja siempre: cubre tanto CASE-sentencia (→ END CASE)
        // como CASE-expresión (→ END simple, ej.: v := CASE…END).
        _blocks.add((line: t.line, type: 'CASE'));

      // ── END con look-ahead ─────────────────────────────────────────────────
      case _PlTok.end:
        _handleEnd(t);

      // ── No modifican el stack ──────────────────────────────────────────────
      case _PlTok.kElsif:
      case _PlTok.kElse:
      case _PlTok.kThen:
      case _PlTok.kFor:
      case _PlTok.kWhile:
      case _PlTok.kWhen:
      case _PlTok.kDeclare:
      case _PlTok.kException:
      case _PlTok.semi:
      case _PlTok.ident:
        break;
    }
  }

  // ── Manejo de END ─────────────────────────────────────────────────────────
  //
  // Look-ahead sobre el siguiente token para determinar qué tipo de bloque cierra.
  // Si es IF / LOOP / CASE, consume ese token.
  // Si es ident (etiqueta) o ; (END;), trata como END simple.

  void _handleEnd(_PlToken endTok) {
    final next = _peek();
    if (next?.type == _PlTok.kIf) {
      _i++; // consume IF
      _popExpect('IF', endTok.line);
    } else if (next?.type == _PlTok.kLoop) {
      _i++; // consume LOOP
      _popExpect('LOOP', endTok.line);
    } else if (next?.type == _PlTok.kCase) {
      _i++; // consume CASE
      _popExpect('CASE', endTok.line);
    } else {
      // END simple o END <label> — cierra BEGIN o CASE-expresión
      _popBeginOrCase(endTok.line);
    }
  }

  // Cierra [expected]; error si el tope del stack no coincide.
  void _popExpect(String expected, int line) {
    if (_blocks.isEmpty) {
      _err(line, 1, 'END $expected sin bloque $expected abierto');
      return;
    }
    final top = _blocks.removeLast();
    if (top.type != expected) {
      _err(
        line,
        1,
        'END $expected inesperado — '
        'el bloque ${top.type} abierto en línea ${top.line} '
        'requiere END ${top.type}',
      );
    }
  }

  // END simple solo puede cerrar BEGIN o CASE; cualquier otro tipo es error.
  void _popBeginOrCase(int line) {
    if (_blocks.isEmpty) {
      _err(line, 1, 'END sin bloque abierto');
      return;
    }
    final top = _blocks.removeLast();
    if (top.type != 'BEGIN' && top.type != 'CASE') {
      _err(
        line,
        1,
        'END inesperado — '
        'el bloque ${top.type} abierto en línea ${top.line} '
        'requiere END ${top.type}',
      );
    }
  }

  // Siguiente token (sin consumirlo)
  _PlToken? _peek() {
    final j = _i + 1;
    return j < _toks.length ? _toks[j] : null;
  }

  // ── Reporte de estructuras sin cerrar al final del código ─────────────────

  void _reportUnclosed() {
    for (final p in _parens) {
      _err(p.line, p.col, '( sin ) correspondiente');
    }
    // Reportar en orden inverso de apertura (más interno primero)
    for (final b in _blocks.reversed) {
      _err(b.line, 1, '${b.type} sin END correspondiente');
    }
  }

  void _err(int line, int col, String msg) =>
      _errs.add(_SyntaxError(line: line, col: col, message: msg));
}
