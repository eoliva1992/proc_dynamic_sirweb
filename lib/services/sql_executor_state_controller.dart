import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sql_execution.dart';
import '../services/sql_executor_service.dart';
import '../services/sql_statement_analyzer.dart';
import '../widgets/app_toast.dart';

/// Controlador de estado y lógica de negocio para la ejecución interactiva
/// de scripts SQL y PL/SQL.
///
/// Desacopla la orquestación de la UI, facilitando pruebas unitarias y
/// mantenimiento modular.
class SqlExecutorStateController extends ChangeNotifier {
  SqlExecutorStateController({
    required String initialAmbiente,
    required String initialSql,
    SqlExecutorService? service,
  }) : _ambiente = initialAmbiente,
       _text = initialSql,
       _svc = service ?? SqlExecutorService() {
    _loadMaxRowsPreference();
    _loadPersistedLog();
  }

  static const _maxRowsPreferenceKey = 'sql_executor_max_rows';
  static const _logHistoryPreferenceKey = 'sql_executor_log_history_v1';
  static const _retentionDays = 7;

  final SqlExecutorService _svc;
  int _logSeq = 0;

  String _ambiente;
  String _text;
  int _cursorLine = 1;
  int _cursorCol = 1;
  bool _running = false;
  int _maxRows = 1000;
  bool _resultsPanelVisible = true;
  double _resultsPanelHeight = 240;

  int _selectedTabIndex = 0;
  void Function(int index)? onTabChangeRequested;

  SqlQueryResult? _lastResult;
  SqlExplainResult? _lastExplainResult;
  List<SqlExplainPlanNode>? _explainNodes;
  final List<SqlExecutionLogEntry> _log = [];

  // ─── Getters ───────────────────────────────────────────────────────────────
  String get ambiente => _ambiente;
  String get text => _text;
  int get cursorLine => _cursorLine;
  int get cursorCol => _cursorCol;
  bool get running => _running;
  int get maxRows => _maxRows;
  bool get resultsPanelVisible => _resultsPanelVisible;
  double get resultsPanelHeight => _resultsPanelHeight;
  int get selectedTabIndex => _selectedTabIndex;
  SqlQueryResult? get lastResult => _lastResult;
  SqlExplainResult? get lastExplainResult => _lastExplainResult;
  List<SqlExplainPlanNode>? get explainNodes => _explainNodes;
  List<SqlExecutionLogEntry> get log => List.unmodifiable(_log);

  // ─── Modificadores de Estado ───────────────────────────────────────────────
  void setAmbiente(String value) {
    if (_ambiente == value) return;
    _ambiente = value;
    notifyListeners();
  }

  void setText(String value) {
    _text = value;
    notifyListeners();
  }

  void setCursor(int line, int col) {
    if (_cursorLine == line && _cursorCol == col) return;
    _cursorLine = line;
    _cursorCol = col;
    notifyListeners();
  }

  void setResultsPanelVisible(bool visible) {
    if (_resultsPanelVisible == visible) return;
    _resultsPanelVisible = visible;
    notifyListeners();
  }

  void toggleResultsPanel() {
    _resultsPanelVisible = !_resultsPanelVisible;
    notifyListeners();
  }

  void setResultsPanelHeight(double height) {
    final clamped = height.clamp(140.0, 700.0);
    if (_resultsPanelHeight == clamped) return;
    _resultsPanelHeight = clamped;
    notifyListeners();
  }

  Future<void> setMaxRows(int value) async {
    if (value < 1 || value > 100000 || _maxRows == value) return;
    _maxRows = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_maxRowsPreferenceKey, value);
    } catch (_) {}
  }

  Future<void> _loadMaxRowsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_maxRowsPreferenceKey);
      if (saved != null && saved >= 1 && saved <= 100000) {
        _maxRows = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _switchTab(int index) {
    _selectedTabIndex = index;
    onTabChangeRequested?.call(index);
    notifyListeners();
  }

  // ─── Análisis de Sentencias ────────────────────────────────────────────────
  int _offsetOf(int line, int col) {
    final lines = _text.split('\n');
    var offset = 0;
    for (var i = 0; i < line - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    return offset + (col - 1);
  }

  SqlStatement? currentStatement() {
    if (_text.trim().isEmpty) return null;
    return statementAtCursor(_text, _offsetOf(_cursorLine, _cursorCol));
  }

  // ─── Ejecución ─────────────────────────────────────────────────────────────
  Future<void> runCurrentOrSelection() async {
    final stmt = currentStatement();
    if (stmt == null) {
      AppToast.info('No hay ninguna sentencia para ejecutar');
      return;
    }
    await runStatement(stmt);
  }

  Future<void> runAll() async {
    final statements = splitStatements(_text);
    if (statements.isEmpty) {
      AppToast.info('El editor está vacío');
      return;
    }
    for (final stmt in statements) {
      await runStatement(stmt);
    }
  }

  Future<void> runStatement(SqlStatement stmt) async {
    if (_running) return;
    _running = true;
    _resultsPanelVisible = true;
    final entry = SqlExecutionLogEntry(
      id: _logSeq++,
      timestamp: DateTime.now(),
      ambiente: _ambiente,
      kind: stmt.kind,
      statementPreview: _preview(stmt.text),
      status: SqlLogStatus.running,
    );
    _log.add(entry);
    notifyListeners();

    try {
      switch (stmt.kind) {
        case SqlStatementKind.select:
          final result = await _svc.executeSelect(
            stmt.text,
            ambiente: _ambiente,
            maxRows: _maxRows,
          );
          _lastResult = result;
          entry
            ..status = SqlLogStatus.success
            ..durationMs = result.durationMs
            ..rowsAffectedOrReturned = result.returnedRows
            ..message = 'OK';
          _switchTab(0);

        case SqlStatementKind.dml:
        case SqlStatementKind.ddl:
          final result = await _svc.executeDml(stmt.text, ambiente: _ambiente);
          entry
            ..status = SqlLogStatus.success
            ..durationMs = result.durationMs
            ..rowsAffectedOrReturned = result.rowsAffected
            ..message = result.message ?? 'OK';
          _switchTab(1);

        case SqlStatementKind.plsql:
          final result = await _svc.executePlSql(
            stmt.text,
            ambiente: _ambiente,
          );
          entry
            ..status = result.errorOracle == null
                ? SqlLogStatus.success
                : SqlLogStatus.error
            ..durationMs = result.duracionMs
            ..message = result.errorOracle ?? result.traza.join('\n');
          _switchTab(1);

        case SqlStatementKind.explainPlan:
          await _explainPlanFor(stmt.text, entry);

        case SqlStatementKind.unknown:
          entry
            ..status = SqlLogStatus.warning
            ..message = 'No se pudo determinar el tipo de sentencia';
          _switchTab(1);
      }
    } on SqlServiceNotImplementedException catch (e) {
      entry
        ..status = SqlLogStatus.warning
        ..message = e.message;
      _switchTab(1);
    } catch (e) {
      entry
        ..status = SqlLogStatus.error
        ..message = e.toString().replaceFirst('Exception: ', '');
      _switchTab(1);
    } finally {
      _running = false;
      _savePersistedLog();
      notifyListeners();
    }
  }

  Future<void> _explainPlanFor(String sql, SqlExecutionLogEntry entry) async {
    try {
      final explainRes = await _svc.explainPlan(sql, ambiente: _ambiente);
      _lastExplainResult = explainRes;
      _explainNodes = explainRes.rows.isNotEmpty
          ? explainRes.rows
          : explainRes.tree;
      entry
        ..status = SqlLogStatus.success
        ..durationMs = explainRes.durationMs
        ..message =
            'Plan generado (${_explainNodes?.length ?? 0} operaciones, ${explainRes.durationMs} ms)';
      _switchTab(2);
    } on SqlServiceNotImplementedException catch (e) {
      entry
        ..status = SqlLogStatus.warning
        ..message = e.message;
    } catch (e) {
      entry
        ..status = SqlLogStatus.error
        ..message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _running = false;
      _savePersistedLog();
      notifyListeners();
    }
  }

  Future<void> runExplainPlan() async {
    if (_running) return;
    final stmt = currentStatement();
    if (stmt == null || stmt.kind != SqlStatementKind.select) {
      AppToast.info('Ubicá el cursor sobre un SELECT para ver su plan');
      return;
    }
    _running = true;
    _resultsPanelVisible = true;
    final entry = SqlExecutionLogEntry(
      id: _logSeq++,
      timestamp: DateTime.now(),
      ambiente: _ambiente,
      kind: SqlStatementKind.explainPlan,
      statementPreview: _preview(stmt.text),
      status: SqlLogStatus.running,
    );
    _log.add(entry);
    notifyListeners();
    await _explainPlanFor(stmt.text, entry);
  }

  void clearOutput() {
    _log.clear();
    _lastResult = null;
    _lastExplainResult = null;
    _explainNodes = null;
    _savePersistedLog();
    notifyListeners();
  }

  Future<void> _loadPersistedLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_logHistoryPreferenceKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw) as List?;
      if (decoded == null) return;

      final cutoff = DateTime.now().subtract(
        const Duration(days: _retentionDays),
      );
      final loaded = <SqlExecutionLogEntry>[];
      var maxId = 0;

      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            final entry = SqlExecutionLogEntry.fromJson(item);
            if (entry.timestamp.isAfter(cutoff)) {
              loaded.add(entry);
              if (entry.id > maxId) maxId = entry.id;
            }
          } catch (_) {}
        }
      }

      if (loaded.isNotEmpty) {
        _log.clear();
        _log.addAll(loaded);
        _logSeq = maxId + 1;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _savePersistedLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cutoff = DateTime.now().subtract(
        const Duration(days: _retentionDays),
      );
      // Guardar entradas de los últimos 7 días (máximo 500 para proteger espacio)
      final valid = _log.where((e) => e.timestamp.isAfter(cutoff)).toList();
      final toSave = valid.length > 500
          ? valid.sublist(valid.length - 500)
          : valid;
      final encoded = jsonEncode(toSave.map((e) => e.toJson()).toList());
      await prefs.setString(_logHistoryPreferenceKey, encoded);
    } catch (_) {}
  }

  String _preview(String text) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length > 120 ? '${oneLine.substring(0, 120)}…' : oneLine;
  }
}
