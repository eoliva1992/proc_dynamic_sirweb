import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sql_execution.dart';
import '../providers/procedimientos_provider.dart';
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

  /// Inyectado por la página: consulta el texto actualmente seleccionado en
  /// el editor Monaco (o `null`/vacío si no hay selección).
  Future<String?> Function()? getSelectedText;

  /// Inyectado por la página: si no hay `cdUsuario` configurado, muestra el
  /// diálogo de identificación y devuelve `true` si quedó configurado al
  /// cerrarse (para reintentar la acción pendiente).
  Future<bool> Function()? ensureUsuario;

  /// Inyectado por la página: pide confirmación antes de ejecutar DML/DDL/
  /// PL-SQL en ambiente Producción. Devuelve `true` para continuar.
  Future<bool> Function(SqlStatement stmt)? confirmProdExecution;

  DateTime? _runStartedAt;
  DateTime? get runStartedAt => _runStartedAt;

  // Texto del script al momento de la última ejecución: permite detectar
  // ediciones posteriores aún no corridas (ver `hasUnexecutedChanges`).
  String? _lastRunText;
  bool get hasUnexecutedChanges =>
      _lastRunText != null && _lastRunText != _text;

  SqlExplainResult? _lastExplainResult;
  List<SqlExplainPlanNode>? _explainNodes;
  final List<SqlExecutionLogEntry> _log = [];

  int _resultSeq = 0;
  final List<SqlNamedResult> _results = [];
  int _selectedResultIndex = 0;

  // Caché de `splitStatements(_text)`, invalidada solo cuando `_text` cambia
  // (evita repetir el escaneo completo del script en cada rebuild/getter).
  String? _statementsCacheText;
  List<SqlStatement>? _statementsCache;

  /// Sesión Oracle abierta por el último DML/DDL/PL-SQL ejecutado con
  /// `confirmar: false`. Sigue viva hasta `commit()`/`rollback()`.
  String? _sessionId;

  // ─── Getters ───────────────────────────────────────────────────────────────
  String? get sessionId => _sessionId;
  bool get hasPendingChanges => _sessionId != null;
  String get ambiente => _ambiente;
  String get text => _text;
  int get cursorLine => _cursorLine;
  int get cursorCol => _cursorCol;
  bool get running => _running;
  int get maxRows => _maxRows;
  bool get resultsPanelVisible => _resultsPanelVisible;
  double get resultsPanelHeight => _resultsPanelHeight;
  int get selectedTabIndex => _selectedTabIndex;
  List<SqlNamedResult> get results => List.unmodifiable(_results);
  int get selectedResultIndex =>
      _results.isEmpty ? 0 : _selectedResultIndex.clamp(0, _results.length - 1);
  SqlQueryResult? get lastResult =>
      _results.isEmpty ? null : _results[selectedResultIndex].result;
  SqlExplainResult? get lastExplainResult => _lastExplainResult;
  List<SqlExplainPlanNode>? get explainNodes => _explainNodes;
  List<SqlExecutionLogEntry> get log => List.unmodifiable(_log);

  // Se incrementa en cada `notifyListeners()` salvo `setText`/`setCursor`:
  // permite a la UI cachear el subárbol del workspace (panel de resultados,
  // Monaco) y sólo reconstruirlo cuando cambia algo relevante, no en cada tecla.
  int _revision = 0;
  int get revision => _revision;
  bool _suppressRevisionBump = false;

  @override
  void notifyListeners() {
    if (!_suppressRevisionBump) _revision++;
    super.notifyListeners();
  }

  // ─── Modificadores de Estado ───────────────────────────────────────────────
  void setAmbiente(String value) {
    if (_ambiente == value) return;
    _ambiente = value;
    // Una sesión abierta no cruza ambientes.
    _sessionId = null;
    notifyListeners();
  }

  void setText(String value) {
    _text = value;
    _suppressRevisionBump = true;
    try {
      notifyListeners();
    } finally {
      _suppressRevisionBump = false;
    }
  }

  void setCursor(int line, int col) {
    if (_cursorLine == line && _cursorCol == col) return;
    _cursorLine = line;
    _cursorCol = col;
    _suppressRevisionBump = true;
    try {
      notifyListeners();
    } finally {
      _suppressRevisionBump = false;
    }
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

  /// Activa la sub-pestaña de resultados en `index` (uno por cada SELECT
  /// ejecutado).
  void selectResult(int index) {
    if (index < 0 || index >= _results.length) return;
    _selectedResultIndex = index;
    notifyListeners();
  }

  // ─── Análisis de Sentencias ────────────────────────────────────────────────
  /// Sentencias del script actual (cacheadas por texto; ver `_statementsCache`).
  List<SqlStatement> get statements {
    if (!identical(_statementsCacheText, _text)) {
      _statementsCache = splitStatements(_text);
      _statementsCacheText = _text;
    }
    return _statementsCache!;
  }

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
    final offset = _offsetOf(_cursorLine, _cursorCol);
    final stmts = statements;
    for (final s in stmts) {
      if (offset >= s.startOffset && offset <= s.endOffset) return s;
    }
    return stmts.isNotEmpty ? stmts.last : null;
  }

  // ─── Ejecución ─────────────────────────────────────────────────────────────
  Future<void> runCurrentOrSelection() async {
    final selected = (await getSelectedText?.call())?.trim();
    if (selected != null && selected.isNotEmpty) {
      // Se divide igual que un script (no requiere ';' final) y cada
      // sentencia resultante se ejecuta por separado, ignorando el resto
      // del texto del editor.
      final statements = splitStatements(selected);
      if (statements.isEmpty) {
        AppToast.info('No hay ninguna sentencia para ejecutar');
        return;
      }
      for (final stmt in statements) {
        await runStatement(stmt);
      }
      return;
    }
    final stmt = currentStatement();
    if (stmt == null) {
      AppToast.info('No hay ninguna sentencia para ejecutar');
      return;
    }
    await runStatement(stmt);
  }

  Future<void> runAll() async {
    final statements = this.statements;
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
    final owner = await _requireOwner();
    if (owner == null) return;
    final isWriteKind =
        stmt.kind == SqlStatementKind.dml ||
        stmt.kind == SqlStatementKind.ddl ||
        stmt.kind == SqlStatementKind.plsql;
    if (isWriteKind && _ambiente == 'Prod' && confirmProdExecution != null) {
      final confirmed = await confirmProdExecution!(stmt);
      if (!confirmed) return;
    }
    _running = true;
    _resultsPanelVisible = true;
    _runStartedAt = DateTime.now();
    _lastRunText = _text;
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
            owner: owner,
            maxRows: _maxRows,
          );
          _results.add(
            SqlNamedResult(
              id: _resultSeq++,
              label: _preview(stmt.text),
              result: result,
            ),
          );
          _selectedResultIndex = _results.length - 1;
          entry
            ..status = SqlLogStatus.success
            ..durationMs = result.durationMs
            ..rowsAffectedOrReturned = result.returnedRows
            ..message = 'OK';
          _switchTab(0);

        case SqlStatementKind.dml:
          final result = await _svc.executeDml(
            stmt.text,
            ambiente: _ambiente,
            owner: owner,
            sessionId: _sessionId,
            maxRows: _maxRows,
          );
          _sessionId = result.sessionId ?? _sessionId;
          entry
            ..status = SqlLogStatus.success
            ..durationMs = result.durationMs
            ..rowsAffectedOrReturned = result.rowsAffected
            ..message = result.message ?? 'OK';
          _switchTab(1);

        case SqlStatementKind.ddl:
          final result = await _svc.executeDdl(
            stmt.text,
            ambiente: _ambiente,
            owner: owner,
          );
          entry
            ..status = result.errors.isEmpty
                ? SqlLogStatus.success
                : SqlLogStatus.error
            ..durationMs = result.durationMs
            ..message = result.errors.isNotEmpty
                ? result.errors.join('; ')
                : 'OK';
          _switchTab(1);

        case SqlStatementKind.plsql:
          final result = await _svc.executePlSql(
            stmt.text,
            ambiente: _ambiente,
            owner: owner,
            sessionId: _sessionId,
          );
          _sessionId = result.sessionId ?? _sessionId;
          entry
            ..status = SqlLogStatus.success
            ..durationMs = result.durationMs
            ..message = result.dbmsOutput.isNotEmpty
                ? result.dbmsOutput.join('\n')
                : 'OK';
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
      _runStartedAt = null;
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
      _runStartedAt = null;
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
    _runStartedAt = DateTime.now();
    _lastRunText = _text;
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
    _results.clear();
    _selectedResultIndex = 0;
    _lastExplainResult = null;
    _explainNodes = null;
    _savePersistedLog();
    notifyListeners();
  }

  /// Confirma la transacción abierta por el último DML/PL-SQL ejecutado.
  Future<void> commit() => _resolveSession('commit');

  /// Descarta la transacción abierta por el último DML/PL-SQL ejecutado.
  Future<void> rollback() => _resolveSession('rollback');

  Future<void> _resolveSession(String action) async {
    final sessionId = _sessionId;
    if (sessionId == null || _running) return;
    final owner = await _requireOwner();
    if (owner == null) return;
    _running = true;
    final entry = SqlExecutionLogEntry(
      id: _logSeq++,
      timestamp: DateTime.now(),
      ambiente: _ambiente,
      kind: SqlStatementKind.unknown,
      statementPreview: action == 'commit' ? 'COMMIT' : 'ROLLBACK',
      status: SqlLogStatus.running,
    );
    _log.add(entry);
    notifyListeners();
    try {
      if (action == 'commit') {
        await _svc.commitSession(sessionId, owner: owner);
      } else {
        await _svc.rollbackSession(sessionId, owner: owner);
      }
      _sessionId = null;
      entry
        ..status = SqlLogStatus.success
        ..message = action == 'commit'
            ? 'Cambios confirmados'
            : 'Cambios descartados';
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

  /// Obtiene el `cdUsuario` configurado (requerido como `owner` por el
  /// backend). Si está vacío, pide a la página que muestre el diálogo de
  /// identificación; devuelve `null` si sigue vacío o no se configuró.
  Future<String?> _requireOwner() async {
    var usuario = procedimientosProvider.cdUsuario.trim();
    if (usuario.isNotEmpty) return usuario;
    final confirmado = await ensureUsuario?.call() ?? false;
    if (!confirmado) return null;
    usuario = procedimientosProvider.cdUsuario.trim();
    return usuario.isEmpty ? null : usuario;
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
