import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sql_execution.dart';
import '../models/sql_http_trace.dart';
import '../providers/procedimientos_provider.dart';
import '../services/sirweb_service.dart' show SirwebCancelledException;
import '../services/sql_executor_service.dart';
import '../services/sql_session_manager.dart';
import '../services/sql_statement_analyzer.dart';
import '../widgets/app_toast.dart';
import '../widgets/editor_split_container.dart';

/// Detecta si una excepción del servidor indica que la sesión SQL expiró, no existe
/// o quedó inválida.
bool _isSessionExpiredError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('no existe') ||
      msg.contains('expir') ||
      msg.contains('invalida') ||
      msg.contains('not found');
}

/// Controlador de estado y lógica de negocio para la ejecución interactiva
/// de scripts SQL y PL/SQL.
///
/// Desacopla la orquestación de la UI, facilitando pruebas unitarias y
/// mantenimiento modular.
class SqlExecutorStateController extends ChangeNotifier {
  SqlExecutorStateController({
    required String initialAmbiente,
    required String initialSql,
    String? initialFilePath,
    SqlExecutorService? service,
    SqlSessionManager? sessionManager,
  }) : _ambiente = initialAmbiente,
       _text = initialSql,
       _currentFilePath = initialFilePath,
       _svc = service ?? SqlExecutorService(),
       _sessionMgr = sessionManager ?? SqlSessionManager.instance {
    _sessionMgr.addListener(_onSessionManagerChanged);
    _loadMaxRowsPreference();
    _loadTimeoutPreference();
    _loadPersistedLog();
    _loadPanelPreferences();
    _setupTraceListener();
  }

  void _setupTraceListener() {
    _svc.onHttpTrace = (trace) {
      final idx = _httpTraces.indexWhere((t) => t.id == trace.id);
      if (idx >= 0) {
        _httpTraces[idx] = trace;
      } else {
        _httpTraces.add(trace);
      }
      notifyListeners();
    };
  }

  static const _maxRowsPreferenceKey = 'sql_executor_max_rows';
  static const _timeoutSecondsPreferenceKey = 'sql_executor_timeout_seconds';
  static const _logHistoryPreferenceKey = 'sql_executor_log_history_v1';
  static const _panelDetachedPreferenceKey = 'sql_executor_panel_detached';
  static const _panelPinnedPreferenceKey = 'sql_executor_panel_pinned';
  static const _splitModePreferenceKey = 'sql_executor_split_mode';
  static const _splitRatioPreferenceKey = 'sql_executor_split_ratio';
  static const _retentionDays = 7;

  final SqlExecutorService _svc;
  final SqlSessionManager _sessionMgr;
  int _logSeq = 0;

  String _ambiente;
  String _text;
  int _cursorLine = 1;
  int _cursorCol = 1;
  bool _running = false;
  http.Client? _activeClient;
  bool _cancelRequested = false;
  bool _loadingMore = false;
  int _maxRows = 1000;
  int _timeoutSeconds = 60;
  bool _resultsPanelVisible = true;
  double _resultsPanelHeight = 240;
  bool _resultsPanelDetached = false;
  bool _resultsPanelPinned = true;
  EditorSplitMode _splitMode = EditorSplitMode.none;
  double _splitRatio = 0.5;

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

  /// Inyectado por la página: llamado cuando una sentencia DDL termina con errores de compilación,
  /// o con una lista vacía cuando termina con éxito para limpiar los marcadores.
  void Function(SqlStatement stmt, List<SqlDdlError> errors)?
  onDdlCompilationErrors;

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
  final List<SqlHttpTraceEntry> _httpTraces = [];

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

  /// Ruta del archivo local en disco si el script actual está vinculado a uno.
  String? _currentFilePath;

  String get _currentOwner => procedimientosProvider.cdUsuario.trim();

  // ─── Getters ───────────────────────────────────────────────────────────────
  String? get sessionId =>
      _sessionMgr.getSessionId(_ambiente, owner: _currentOwner) ?? _sessionId;
  bool get hasPendingChanges =>
      _sessionMgr.hasPendingChanges(_ambiente, owner: _currentOwner);
  String? get currentFilePath => _currentFilePath;
  String get ambiente => _ambiente;
  String get text => _text;
  int get cursorLine => _cursorLine;
  int get cursorCol => _cursorCol;
  bool get running => _running;
  bool get cancelRequested => _cancelRequested;
  bool get loadingMore => _loadingMore;
  int get maxRows => _maxRows;
  int get timeoutSeconds => _timeoutSeconds;
  bool get resultsPanelVisible => _resultsPanelVisible;
  double get resultsPanelHeight => _resultsPanelHeight;
  bool get resultsPanelDetached => _resultsPanelDetached;
  bool get resultsPanelPinned => _resultsPanelPinned;
  EditorSplitMode get splitMode => _splitMode;
  double get splitRatio => _splitRatio;
  int get selectedTabIndex => _selectedTabIndex;
  List<SqlNamedResult> get results => List.unmodifiable(_results);
  int get selectedResultIndex =>
      _results.isEmpty ? 0 : _selectedResultIndex.clamp(0, _results.length - 1);
  SqlQueryResult? get lastResult =>
      _results.isEmpty ? null : _results[selectedResultIndex].result;
  SqlExplainResult? get lastExplainResult => _lastExplainResult;
  List<SqlExplainPlanNode>? get explainNodes => _explainNodes;
  List<SqlExecutionLogEntry> get log => List.unmodifiable(_log);
  List<SqlHttpTraceEntry> get httpTraces => List.unmodifiable(_httpTraces);

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

  void _onSessionManagerChanged() {
    // Sincroniza _sessionId con el gestor centralizado del ambiente y dueño.
    _sessionId = _sessionMgr.getSessionId(_ambiente, owner: _currentOwner);
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionMgr.removeListener(_onSessionManagerChanged);
    super.dispose();
  }

  // ─── Modificadores de Estado ───────────────────────────────────────────────
  void setAmbiente(String value) {
    if (_ambiente == value) return;
    _ambiente = value;
    // Sincroniza la sesión con el nuevo ambiente y dueño actual.
    _sessionId = _sessionMgr.getSessionId(_ambiente, owner: _currentOwner);
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

  void setCurrentFilePath(String? path) {
    if (_currentFilePath == path) return;
    _currentFilePath = path;
    notifyListeners();
  }

  void loadFromLocalFile({required String path, required String content}) {
    _currentFilePath = path;
    _text = content;
    _cursorLine = 1;
    _cursorCol = 1;
    _statementsCache = null;
    _statementsCacheText = null;
    notifyListeners();
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

  void setResultsPanelDetached(bool detached) {
    if (_resultsPanelDetached == detached) return;
    _resultsPanelDetached = detached;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.setBool(_panelDetachedPreferenceKey, detached);
        })
        .catchError((_) {});
  }

  void toggleResultsPanelDetached() {
    setResultsPanelDetached(!_resultsPanelDetached);
  }

  void setResultsPanelPinned(bool pinned) {
    if (_resultsPanelPinned == pinned) return;
    _resultsPanelPinned = pinned;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.setBool(_panelPinnedPreferenceKey, pinned);
        })
        .catchError((_) {});
  }

  void toggleResultsPanelPinned() {
    setResultsPanelPinned(!_resultsPanelPinned);
  }

  void setSplitMode(EditorSplitMode mode) {
    if (_splitMode == mode) return;
    _splitMode = mode;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.setString(_splitModePreferenceKey, mode.name);
        })
        .catchError((_) {});
  }

  void toggleSplit(EditorSplitMode target) {
    if (_splitMode == target) {
      setSplitMode(EditorSplitMode.none);
    } else {
      setSplitMode(target);
    }
  }

  void closeSplit() {
    setSplitMode(EditorSplitMode.none);
  }

  void setSplitRatio(double ratio) {
    final clamped = ratio.clamp(0.15, 0.85);
    if ((_splitRatio - clamped).abs() < 0.001) return;
    _splitRatio = clamped;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.setDouble(_splitRatioPreferenceKey, clamped);
        })
        .catchError((_) {});
  }

  Future<void> _loadPanelPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final detached = prefs.getBool(_panelDetachedPreferenceKey);
      final pinned = prefs.getBool(_panelPinnedPreferenceKey);
      final savedSplitMode = prefs.getString(_splitModePreferenceKey);
      final savedSplitRatio = prefs.getDouble(_splitRatioPreferenceKey);
      var changed = false;
      if (detached != null && _resultsPanelDetached != detached) {
        _resultsPanelDetached = detached;
        changed = true;
      }
      if (pinned != null && _resultsPanelPinned != pinned) {
        _resultsPanelPinned = pinned;
        changed = true;
      }
      if (savedSplitMode != null) {
        final mode = EditorSplitMode.values.firstWhere(
          (m) => m.name == savedSplitMode,
          orElse: () => EditorSplitMode.none,
        );
        if (_splitMode != mode) {
          _splitMode = mode;
          changed = true;
        }
      }
      if (savedSplitRatio != null &&
          (savedSplitRatio >= 0.15 && savedSplitRatio <= 0.85)) {
        if ((_splitRatio - savedSplitRatio).abs() > 0.001) {
          _splitRatio = savedSplitRatio;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  Future<void> setMaxRows(int value) async {
    if (value != -1 && (value < 1 || value > 100000)) return;
    if (_maxRows == value) return;
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
      if (saved != null && (saved == -1 || (saved >= 1 && saved <= 100000))) {
        _maxRows = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setTimeoutSeconds(int value) async {
    if (value < 5 || value > 3600) return;
    if (_timeoutSeconds == value) return;
    _timeoutSeconds = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_timeoutSecondsPreferenceKey, value);
    } catch (_) {}
  }

  Future<void> _loadTimeoutPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_timeoutSecondsPreferenceKey);
      if (saved != null && saved >= 5 && saved <= 3600) {
        _timeoutSeconds = saved;
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

  /// Carga el siguiente bloque de filas para el resultado activo si fue truncado.
  Future<bool> loadMoreRows() async {
    if (_loadingMore || _running || _results.isEmpty) return false;
    final idx = _selectedResultIndex.clamp(0, _results.length - 1);
    final namedResult = _results[idx];
    final currentResult = namedResult.result;

    if (!currentResult.truncated || namedResult.statementText.trim().isEmpty) {
      return false;
    }

    var owner = _currentOwner;
    if (owner.isEmpty) {
      final resolved = await _requireOwner();
      if (resolved == null) return false;
      owner = resolved;
    }

    _loadingMore = true;
    notifyListeners();

    final client = http.Client();
    _activeClient = client;

    try {
      final offset = currentResult.rows.length;
      final limit = _maxRows > 0 ? _maxRows : 1000;
      final pagedSql = buildPagedSelectSql(
        namedResult.statementText,
        offset: offset,
        limit: limit,
      );

      final nextResult = await _svc.executeSelect(
        pagedSql,
        ambiente: _ambiente,
        owner: _currentOwner,
        sessionId: sessionId,
        maxRows: limit,
        timeoutSegundos: _timeoutSeconds,
        client: client,
        cancelado: () => _cancelRequested,
      );

      _sessionMgr.touch(_ambiente, owner: _currentOwner);

      // Anexar las nuevas filas manteniendo intactas las columnas y el ID de resultado
      final updatedResult = currentResult.appendRows(
        nextResult.rows,
        truncated: nextResult.truncated,
        additionalDurationMs: nextResult.durationMs,
      );

      _results[idx] = namedResult.withResult(updatedResult);

      final entry = SqlExecutionLogEntry(
        id: _logSeq++,
        timestamp: DateTime.now(),
        ambiente: _ambiente,
        kind: SqlStatementKind.select,
        statementPreview:
            'FETCH NEXT $limit ROWS (offset $offset) · ${_preview(namedResult.statementText)}',
        status: SqlLogStatus.success,
        durationMs: nextResult.durationMs,
        rowsAffectedOrReturned: nextResult.returnedRows,
        message:
            'Lote cargado: +${nextResult.returnedRows} filas (Total: ${updatedResult.rows.length})',
      );
      _log.add(entry);

      return true;
    } catch (e) {
      final entry = SqlExecutionLogEntry(
        id: _logSeq++,
        timestamp: DateTime.now(),
        ambiente: _ambiente,
        kind: SqlStatementKind.select,
        statementPreview: 'FETCH NEXT (offset ${currentResult.rows.length})',
        status: SqlLogStatus.error,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
      _log.add(entry);
      return false;
    } finally {
      client.close();
      if (identical(_activeClient, client)) _activeClient = null;
      _loadingMore = false;
      notifyListeners();
    }
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
      _clearResultsForRun();
      for (final stmt in statements) {
        if (_cancelRequested) break;
        await _executeStatement(stmt);
        if (_cancelRequested) break;
      }
      return;
    }
    final stmt = currentStatement();
    if (stmt == null) {
      AppToast.info('No hay ninguna sentencia para ejecutar');
      return;
    }
    _clearResultsForRun();
    await _executeStatement(stmt);
  }

  Future<void> runAll() async {
    final statements = this.statements;
    if (statements.isEmpty) {
      AppToast.info('El editor está vacío');
      return;
    }
    _clearResultsForRun();
    for (final stmt in statements) {
      if (_cancelRequested) break;
      await _executeStatement(stmt);
      if (_cancelRequested) break;
    }
  }

  /// Cancela la ejecución de la sentencia o lote de sentencias actualmente
  /// en curso, abortando inmediatamente la petición HTTP activa.
  void cancel() {
    if (!_running) return;
    _cancelRequested = true;
    _activeClient?.close();
    _activeClient = null;
    notifyListeners();
    try {
      AppToast.info('Ejecución cancelada');
    } catch (_) {}
  }

  void _clearResultsForRun() {
    _results.clear();
    _selectedResultIndex = 0;
  }

  Future<void> runStatement(
    SqlStatement stmt, {
    bool clearPreviousResults = true,
  }) async {
    if (clearPreviousResults) {
      _clearResultsForRun();
    }
    await _executeStatement(stmt);
  }

  Future<void> _executeStatement(SqlStatement stmt) async {
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
    _cancelRequested = false;
    final client = http.Client();
    _activeClient = client;
    _resultsPanelVisible = true;
    _runStartedAt = DateTime.now();
    _lastRunText = _text;
    onDdlCompilationErrors?.call(stmt, const []);
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
      var currentSessionId = sessionId;
      var attempt = 0;
      const maxAttempts = 2;

      while (attempt < maxAttempts) {
        attempt++;
        try {
          switch (stmt.kind) {
            case SqlStatementKind.select:
              final result = await _svc.executeSelect(
                stmt.text,
                ambiente: _ambiente,
                owner: owner,
                sessionId: currentSessionId,
                maxRows: _maxRows,
                timeoutSegundos: _timeoutSeconds,
                client: client,
                cancelado: () => _cancelRequested,
              );
              _sessionMgr.touch(_ambiente, owner: owner);
              _results.add(
                SqlNamedResult(
                  id: _resultSeq++,
                  label: _preview(stmt.text),
                  result: result,
                  statementText: stmt.text,
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
                sessionId: currentSessionId,
                maxRows: _maxRows,
                timeoutSegundos: _timeoutSeconds,
                client: client,
                cancelado: () => _cancelRequested,
              );
              final updatedSessionId = result.sessionId ?? currentSessionId;
              _sessionId = updatedSessionId;
              _sessionMgr.setSessionId(
                _ambiente,
                updatedSessionId,
                owner: owner,
                hasPendingChanges:
                    result.pendingCommit || (result.rowsAffected > 0),
              );
              entry
                ..status = SqlLogStatus.success
                ..durationMs = result.durationMs
                ..rowsAffectedOrReturned = result.rowsAffected
                ..message = result.message ?? 'OK';
              _switchTab(1);

            case SqlStatementKind.ddl:
              final target = extractDdlTarget(stmt.text);
              final result = await _svc.executeDdl(
                stmt.text,
                ambiente: _ambiente,
                owner: owner,
                sessionId: currentSessionId,
                objectName: target.objectName,
                objectType: target.objectType,
                timeoutSegundos: _timeoutSeconds,
                client: client,
                cancelado: () => _cancelRequested,
              );
              _sessionMgr.touch(_ambiente, owner: owner);
              final hasErrors = result.errors.isNotEmpty;
              entry
                ..status = hasErrors ? SqlLogStatus.error : SqlLogStatus.success
                ..durationMs = result.durationMs
                ..message = hasErrors
                    ? result.errors.map((e) => e.toString()).join('\n')
                    : 'OK';
              onDdlCompilationErrors?.call(stmt, result.errors);
              _switchTab(1);

            case SqlStatementKind.plsql:
              final result = await _svc.executePlSql(
                stmt.text,
                ambiente: _ambiente,
                owner: owner,
                sessionId: currentSessionId,
                timeoutSegundos: _timeoutSeconds,
                client: client,
                cancelado: () => _cancelRequested,
              );
              final updatedSessionId = result.sessionId ?? currentSessionId;
              _sessionId = updatedSessionId;
              _sessionMgr.setSessionId(
                _ambiente,
                updatedSessionId,
                owner: owner,
                hasPendingChanges: result.pendingCommit,
              );
              entry
                ..status = SqlLogStatus.success
                ..durationMs = result.durationMs
                ..message = result.dbmsOutput.isNotEmpty
                    ? result.dbmsOutput.join('\n')
                    : 'OK';
              _switchTab(1);

            case SqlStatementKind.command:
              final cmdResult = await _svc.executeCommand(
                stmt.text,
                ambiente: _ambiente,
                owner: owner,
                sessionId: currentSessionId,
                timeoutSegundos: _timeoutSeconds,
                client: client,
                cancelado: () => _cancelRequested,
              );
              _sessionMgr.touch(_ambiente, owner: owner);
              final queryResult = cmdResult.toSqlQueryResult();
              _results.add(
                SqlNamedResult(
                  id: _resultSeq++,
                  label: _preview(stmt.text),
                  result: queryResult,
                  statementText: stmt.text,
                ),
              );
              _selectedResultIndex = _results.length - 1;
              entry
                ..status = SqlLogStatus.success
                ..durationMs = cmdResult.durationMs
                ..rowsAffectedOrReturned = cmdResult.columns.isNotEmpty
                    ? cmdResult.columns.length
                    : 1
                ..message = cmdResult.output.isNotEmpty
                    ? cmdResult.output
                    : 'OK';
              _switchTab(0);

            case SqlStatementKind.explainPlan:
              await _explainPlanFor(
                stmt.text,
                entry,
                client: client,
                cancelado: () => _cancelRequested,
              );

            case SqlStatementKind.unknown:
              entry
                ..status = SqlLogStatus.warning
                ..message = 'No se pudo determinar el tipo de sentencia';
              _switchTab(1);
          }
          break; // Ejecución exitosa, sale del bucle de reintento.
        } on SirwebCancelledException {
          entry
            ..status = SqlLogStatus.warning
            ..message = 'Operación cancelada por el usuario';
          _switchTab(1);
          break;
        } on SqlServiceNotImplementedException catch (e) {
          entry
            ..status = SqlLogStatus.warning
            ..message = e.message;
          _switchTab(1);
          break;
        } catch (e) {
          // Si el fallo se debe a que la sesión expiró o no existe y se envió un sessionId,
          // limpiamos la sesión expirada y reintentamos de inmediato con sessionId = null.
          if (currentSessionId != null &&
              _isSessionExpiredError(e) &&
              attempt < maxAttempts &&
              !_cancelRequested) {
            _sessionId = null;
            _sessionMgr.clearSession(_ambiente, owner: owner);
            currentSessionId = null;
            continue; // Reintento con nueva sesión (sessionId = null)
          }

          if (_cancelRequested) {
            entry
              ..status = SqlLogStatus.warning
              ..message = 'Operación cancelada por el usuario';
          } else {
            entry
              ..status = SqlLogStatus.error
              ..message = e.toString().replaceFirst('Exception: ', '');
          }
          _switchTab(1);
          break;
        }
      }
    } finally {
      client.close();
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      _running = false;
      _runStartedAt = null;
      _savePersistedLog();
      notifyListeners();
    }
  }

  Future<void> _explainPlanFor(
    String sql,
    SqlExecutionLogEntry entry, {
    http.Client? client,
    bool Function()? cancelado,
  }) async {
    try {
      final explainRes = await _svc.explainPlan(
        sql,
        ambiente: _ambiente,
        timeoutSegundos: _timeoutSeconds,
        client: client,
        cancelado: cancelado,
      );
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
    } on SirwebCancelledException {
      entry
        ..status = SqlLogStatus.warning
        ..message = 'Operación cancelada por el usuario';
    } on SqlServiceNotImplementedException catch (e) {
      entry
        ..status = SqlLogStatus.warning
        ..message = e.message;
    } catch (e) {
      if (_cancelRequested) {
        entry
          ..status = SqlLogStatus.warning
          ..message = 'Operación cancelada por el usuario';
      } else {
        entry
          ..status = SqlLogStatus.error
          ..message = e.toString().replaceFirst('Exception: ', '');
      }
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
    _cancelRequested = false;
    final client = http.Client();
    _activeClient = client;
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
    try {
      await _explainPlanFor(
        stmt.text,
        entry,
        client: client,
        cancelado: () => _cancelRequested,
      );
    } finally {
      client.close();
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      _running = false;
      _runStartedAt = null;
      notifyListeners();
    }
  }

  void clearOutput() {
    _log.clear();
    _httpTraces.clear();
    _results.clear();
    _selectedResultIndex = 0;
    _lastExplainResult = null;
    _explainNodes = null;
    _savePersistedLog();
    notifyListeners();
  }

  /// Limpia únicamente el historial de logs/mensajes sin alterar los resultados
  /// de consultas activas ni el árbol del Explain Plan.
  void clearLog() {
    _log.clear();
    _savePersistedLog();
    notifyListeners();
  }

  /// Limpia únicamente el historial de trazas de envíos y respuestas HTTP.
  void clearHttpTraces() {
    _httpTraces.clear();
    notifyListeners();
  }

  /// Confirma la transacción abierta por el último DML/PL-SQL ejecutado.
  Future<void> commit() => _resolveSession('commit');

  /// Descarta la transacción abierta por el último DML/PL-SQL ejecutado.
  Future<void> rollback() => _resolveSession('rollback');

  Future<void> _resolveSession(String action) async {
    final activeSessionId = sessionId;
    if (activeSessionId == null || _running) return;
    final owner = await _requireOwner();
    if (owner == null) return;
    _running = true;
    _cancelRequested = false;
    final client = http.Client();
    _activeClient = client;
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
        await _svc.commitSession(
          activeSessionId,
          owner: owner,
          client: client,
          cancelado: () => _cancelRequested,
        );
      } else {
        await _svc.rollbackSession(
          activeSessionId,
          owner: owner,
          client: client,
          cancelado: () => _cancelRequested,
        );
      }
      // La sesión NO se destruye: se mantiene viva en Oracle y en SqlSessionManager,
      // actualizando únicamente el estado de cambios pendientes para ocultar los botones.
      _sessionMgr.markPendingChanges(_ambiente, false, owner: owner);
      entry
        ..status = SqlLogStatus.success
        ..message = action == 'commit'
            ? 'Cambios confirmados'
            : 'Cambios descartados';
    } on SirwebCancelledException {
      entry
        ..status = SqlLogStatus.warning
        ..message = 'Operación cancelada por el usuario';
    } catch (e) {
      final isExpired = _isSessionExpiredError(e);
      if (isExpired) {
        _sessionId = null;
        _sessionMgr.clearSession(_ambiente, owner: owner);
      }
      if (_cancelRequested) {
        entry
          ..status = SqlLogStatus.warning
          ..message = 'Operación cancelada por el usuario';
      } else if (isExpired) {
        entry
          ..status = SqlLogStatus.warning
          ..message =
              'La sesión expiró o ya no existe en el servidor. Se restableció la sesión.';
      } else {
        entry
          ..status = SqlLogStatus.error
          ..message = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      client.close();
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
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
