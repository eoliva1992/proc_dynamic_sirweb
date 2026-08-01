/**
 * checker.js  —  Entry point del bundle ANTLR4 PL/SQL
 *
 * Expone globalThis.__checkPlSql(code):
 *   → JSON string con array de { line, col, msg }
 *   → "[]"  si el código no tiene errores de sintaxis
 *   → "[{...}]" con al menos un error si los hay
 *
 * Se carga en flutter_js (QuickJS) una sola vez al inicializar el motor.
 */

import antlr4 from 'antlr4';
import PlSqlLexer  from '../generated/PlSqlLexer.js';
import PlSqlParser from '../generated/PlSqlParser.js';

// ── Simplificador de mensajes de error de ANTLR4 ──────────────────────────────
// Los mensajes raw de ANTLR4 son técnicos ("mismatched input 'X' expecting {…}").
// Esta función los transforma en mensajes legibles en español.
function humanize(msg) {
  // "mismatched input 'X' expecting {...}"
  let m = msg.match(/mismatched input '(.+?)'/);
  if (m) return `Token inesperado: '${m[1]}'`;

  // "extraneous input 'X' expecting {...}"
  m = msg.match(/extraneous input '(.+?)'/);
  if (m) return `Entrada inesperada: '${m[1]}'`;

  // "missing X at Y"
  m = msg.match(/missing (.+?) at '(.+?)'/);
  if (m) return `Falta ${m[1]} antes de '${m[2]}'`;

  // "no viable alternative at input 'X'"
  m = msg.match(/no viable alternative at input '(.+?)'/);
  if (m) return `Sintaxis no reconocida cerca de '${m[1].slice(0, 40)}'`;

  // "token recognition error at: 'X'"
  m = msg.match(/token recognition error at: '(.+?)'/);
  if (m) return `Caracter no reconocido: '${m[1]}'`;

  return msg;
}

// ── Collector de errores ──────────────────────────────────────────────────────
class ErrorCollector extends antlr4.error.ErrorListener {
  constructor() {
    super();
    this.errors = [];
  }
  syntaxError(_rec, _sym, line, col, msg) {
    this.errors.push({ line, col: col + 1, msg: humanize(msg) });
  }
}

// ── Función expuesta al runtime de flutter_js ─────────────────────────────────
/**
 * Valida la sintaxis PL/SQL de [code].
 *
 * Retorna un JSON array de errores:
 *   [{ "line": N, "col": N, "msg": "..." }, ...]
 *
 * Retorna "[]" si no hay errores.
 */
globalThis.__checkPlSql = function (code) {
  try {
    const chars      = new antlr4.InputStream(code, true);
    const lexer      = new PlSqlLexer(chars);
    const tokens     = new antlr4.CommonTokenStream(lexer);
    const parser     = new PlSqlParser(tokens);

    const lexerErrs  = new ErrorCollector();
    const parserErrs = new ErrorCollector();

    lexer.removeErrorListeners();
    lexer.addErrorListener(lexerErrs);

    parser.removeErrorListeners();
    parser.addErrorListener(parserErrs);

    // Regla raíz: acepta scripts completos, bloques anónimos,
    // CREATE PROCEDURE/FUNCTION, bloques PL/SQL standalone, etc.
    parser.sql_script();

    const all = [...lexerErrs.errors, ...parserErrs.errors];
    // Ordenar por línea, luego por columna
    all.sort((a, b) => a.line !== b.line ? a.line - b.line : a.col - b.col);
    // Limitar a los primeros 20 errores para no saturar el gutter
    return JSON.stringify(all.slice(0, 20));
  } catch (e) {
    return JSON.stringify([{
      line: 1,
      col:  1,
      msg:  'Error interno del parser: ' + String(e.message || e),
    }]);
  }
};
