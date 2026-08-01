import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

// ── Singleton del motor JS ─────────────────────────────────────────────────
// QuickJS en Android/Windows/Linux, JavascriptCore en iOS/macOS.

JavascriptRuntime? _rt;
bool _rtInitialized = false;

// Estado del bundle PL/SQL (cargado de assets de forma asíncrona)
bool _plSqlReady = false;
bool _plSqlLoading = false;

// ── Inicialización del runtime JS ──────────────────────────────────────────

void _initRuntime() {
  if (_rtInitialized) return;
  _rtInitialized = true;
  try {
    _rt = getJavascriptRuntime();
    // Registra el checker de JavaScript (síncrono — no requiere asset).
    _rt!.evaluate(r"""
function __chkSyn(c) {
  try {
    new Function(c);
    return null;
  } catch (e) {
    var msg = String(e.message || 'Error de sintaxis');
    var l = 1, k = 1;
    var s = e.stack || '';
    var m = s.match(/(\d+):(\d+)/);
    if (m) {
      l = Math.max(1, parseInt(m[1], 10) - 2);
      k = Math.max(1, parseInt(m[2], 10));
    }
    return JSON.stringify({ msg: msg, line: l, col: k });
  }
}
""");
  } catch (_) {
    _rt = null;
  }
}

// ── Carga asíncrona del bundle PL/SQL ─────────────────────────────────────
// Debe llamarse una sola vez desde el widget (initState).
// Hasta que complete, evalPlSqlSyntax() devuelve null → fallback manual.

Future<void> initPlSqlEngine() async {
  if (_plSqlReady || _plSqlLoading) return;
  _plSqlLoading = true;
  _initRuntime();
  if (_rt == null) {
    _plSqlLoading = false;
    return;
  }
  try {
    final src = await rootBundle.loadString('assets/plsql_checker.js');
    _rt!.evaluate(src);
    _plSqlReady = true;
  } catch (_) {
    // Asset no existe todavía (bundle no generado) → fallback al checker manual
  } finally {
    _plSqlLoading = false;
  }
}

// ── API pública ───────────────────────────────────────────────────────────

/// Valida [code] JavaScript con el motor embebido.
///
/// Retorna:
/// - `null` → motor no disponible; usar checker manual.
/// - `''`   → código válido.
/// - JSON   → `{"msg":"...","line":N,"col":N}` con el primer error.
String? evalJsSyntax(String code) {
  _initRuntime();
  if (_rt == null) return null;
  try {
    final result = _rt!.evaluate('__chkSyn(${jsonEncode(code)})');
    if (result.isError) return null;
    final s = result.stringResult;
    if (s == 'null' || s == 'undefined' || s.isEmpty) return '';
    return s;
  } catch (_) {
    return null;
  }
}

/// Valida [code] PL/SQL con el parser ANTLR4 embebido.
///
/// Retorna:
/// - `null`        → bundle no cargado; usar checker manual como fallback.
/// - `'[]'`        → sin errores de sintaxis.
/// - JSON array    → `[{"line":N,"col":N,"msg":"..."},...]`.
String? evalPlSqlSyntax(String code) {
  if (!_plSqlReady || _rt == null) return null;
  try {
    final result = _rt!.evaluate('__checkPlSql(${jsonEncode(code)})');
    if (result.isError) return null;
    final s = result.stringResult;
    if (s == 'null' || s == 'undefined' || s.isEmpty) return '[]';
    return s;
  } catch (_) {
    return null;
  }
}
