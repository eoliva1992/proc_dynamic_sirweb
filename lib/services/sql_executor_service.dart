/// Orquesta los 4 servicios de ejecución del Ejecutor SQL/PL-SQL: SELECT,
/// DML/DDL, PL/SQL y EXPLAIN PLAN.
///
/// `executeSelect`, `executeDml`, `executeDdl` y `executePlSql` comparten
/// `POST /tools/sql/statement`. SELECT, DML y PL/SQL envían
/// `confirmar: false`; DDL envía `confirmar: true` porque Oracle puede hacer
/// commit implícito. DML/PL-SQL mantienen transacción bajo `sessionId` hasta
/// `commitSession`/`rollbackSession`. El backend exige `owner` no vacío.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sql_execution.dart';
import '../models/sql_http_trace.dart';
import 'sirweb_service.dart';
import 'sql_statement_analyzer.dart' show stripTrailingSemicolon;

/// Señal de que el servicio todavía no está implementado en el backend.
class SqlServiceNotImplementedException implements Exception {
  const SqlServiceNotImplementedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Envuelve un SELECT original con cláusula de paginación para Oracle.
///
/// Soporta tanto sintaxis moderna estándar (`OFFSET ... ROWS FETCH NEXT ... ROWS ONLY`)
/// como envoltorio compatible con subqueries.
String buildPagedSelectSql(
  String originalSql, {
  required int offset,
  required int limit,
}) {
  final sql = stripTrailingSemicolon(originalSql).trim();
  return 'SELECT * FROM (\n$sql\n) OFFSET $offset ROWS FETCH NEXT $limit ROWS ONLY';
}

class SqlExecutorService {
  static final SqlExecutorService _instance = SqlExecutorService._();
  factory SqlExecutorService() => _instance;
  SqlExecutorService._();

  static final http.Client _client = http.Client();
  static int _httpTraceSeq = 1;

  /// Callback global o por instancia para recibir las trazas HTTP de envíos y respuestas.
  void Function(SqlHttpTraceEntry trace)? onHttpTrace;

  /// `POST /tools/sql/statement` — contrato unificado para SELECT, DML, DDL
  /// y PL/SQL. Devuelve el `data` decodificado de la respuesta.
  Future<Map<String, dynamic>> _postStatement(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    bool confirmar = false,
    Map<String, dynamic>? binds,
    int? maxRowsAffected,
    String? objectName,
    String? objectType,
    Map<String, dynamic>? plSqlBinds,
    bool capturarDbmsOutput = false,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    required String contexto,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/statement');
    final traceCb = onTrace ?? onHttpTrace;

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final requestBodyJson = jsonEncode({
      'owner': owner,
      'sql': sql,
      'ambiente': ambiente,
      'confirmar': confirmar,
      'maxRows': maxRows,
      'timeoutSegundos': timeoutSegundos,
      'capturarDbmsOutput': capturarDbmsOutput,
      ...?sessionId == null ? null : {'sessionId': sessionId},
      ...?binds == null ? null : {'binds': binds},
      ...?maxRowsAffected == null ? null : {'maxRowsAffected': maxRowsAffected},
      ...?objectName == null ? null : {'objectName': objectName},
      ...?objectType == null ? null : {'objectType': objectType},
      ...?plSqlBinds == null ? null : {'plSqlBinds': plSqlBinds},
    });

    final trace = SqlHttpTraceEntry(
      id: _httpTraceSeq++,
      timestamp: DateTime.now(),
      method: 'POST',
      url: uri.toString(),
      endpoint: uri.path,
      requestHeaders: headers,
      requestBody: requestBodyJson,
      status: SqlHttpTraceStatus.running,
    );
    traceCb?.call(trace);

    final sw = Stopwatch()..start();
    http.Response response;
    try {
      final httpClient = client ?? _client;
      response = await SirwebService.guardRequest(
        () => httpClient.post(uri, headers: headers, body: requestBodyJson),
        timeout: Duration(seconds: timeoutSegundos + 15),
        contexto: contexto,
        cancelado: cancelado,
      );
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.statusCode = response.statusCode;
    } on SirwebCancelledException {
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.status = SqlHttpTraceStatus.cancelled;
      trace.error = 'Operación cancelada por el usuario';
      traceCb?.call(trace);
      rethrow;
    } catch (e) {
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.status = SqlHttpTraceStatus.error;
      trace.error = e.toString().replaceFirst('Exception: ', '');
      traceCb?.call(trace);
      rethrow;
    }

    final rawBody = utf8.decode(response.bodyBytes);
    trace.responseBody = rawBody;

    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(rawBody) as Map<String, dynamic>;
    } on FormatException {
      trace.status = SqlHttpTraceStatus.error;
      trace.error = rawBody.trim().isEmpty
          ? 'Error ${response.statusCode} (respuesta vacía)'
          : rawBody.trim();
      traceCb?.call(trace);
      throw Exception(
        rawBody.trim().isEmpty
            ? 'Error ${response.statusCode} al ejecutar la sentencia (respuesta vacía)'
            : rawBody.trim(),
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['success'] == false) {
      final msg =
          envelope['error']?.toString() ??
          envelope['message']?.toString() ??
          'Error ${response.statusCode} al ejecutar la sentencia';
      trace.status = SqlHttpTraceStatus.error;
      trace.error = msg;
      traceCb?.call(trace);
      throw Exception(msg);
    }

    trace.status = SqlHttpTraceStatus.success;
    traceCb?.call(trace);

    return envelope['data'] as Map<String, dynamic>? ?? const {};
  }

  /// Ejecuta un SELECT y devuelve columnas + filas (`data.query`).
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final cleanSql = stripTrailingSemicolon(sql);
    final data = await _postStatement(
      cleanSql,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      maxRows: maxRows,
      timeoutSegundos: timeoutSegundos,
      client: client,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb',
      onTrace: onTrace,
    );
    final query = data['query'];
    if (query is Map<String, dynamic>) return SqlQueryResult.fromJson(query);
    return SqlQueryResult.empty;
  }

  /// Ejecuta un DML (`data.dml`): deja la transacción abierta bajo
  /// `sessionId` hasta que se confirme o descarte explícitamente.
  Future<SqlDmlResult> executeDml(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final cleanSql = stripTrailingSemicolon(sql);
    final data = await _postStatement(
      cleanSql,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      maxRowsAffected: maxRows,
      maxRows: maxRows,
      timeoutSegundos: timeoutSegundos,
      client: client,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb',
      onTrace: onTrace,
    );
    final dml = data['dml'];
    if (dml is Map<String, dynamic>) return SqlDmlResult.fromJson(dml);
    return const SqlDmlResult(rowsAffected: 0, durationMs: 0);
  }

  /// Ejecuta un DDL (`data.ddl`): el backend exige `confirmar: true` porque
  /// Oracle realiza commit implícito al ejecutar DDL (no hay `sessionId`/`pendingCommit`).
  Future<SqlDdlResult> executeDdl(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    String? objectName,
    String? objectType,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final data = await _postStatement(
      sql,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      confirmar: true,
      objectName: objectName,
      objectType: objectType,
      timeoutSegundos: timeoutSegundos,
      client: client,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb',
      onTrace: onTrace,
    );
    final ddl = data['ddl'];
    if (ddl is Map<String, dynamic>) {
      // Propaga mensaje de advertencia del sobre o de ddl si vino a nivel superior
      final ddlMap = Map<String, dynamic>.from(ddl);
      if ((ddlMap['errors'] == null ||
              (ddlMap['errors'] is List &&
                  (ddlMap['errors'] as List).isEmpty)) &&
          data['errors'] != null) {
        ddlMap['errors'] = data['errors'];
      }
      return SqlDdlResult.fromJson(ddlMap);
    }
    return SqlDdlResult(
      ambiente: ambiente,
      confirmed: false,
      autoCommitPossible: false,
      durationMs: 0,
    );
  }

  /// Ejecuta un bloque PL/SQL anónimo (`data.plSql`), capturando
  /// `DBMS_OUTPUT.PUT_LINE`.
  Future<SqlPlSqlResult> executePlSql(
    String plsqlBlock, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final data = await _postStatement(
      plsqlBlock,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      capturarDbmsOutput: true,
      timeoutSegundos: timeoutSegundos,
      client: client,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb (PL/SQL)',
      onTrace: onTrace,
    );
    final plSql = data['plSql'];
    if (plSql is Map<String, dynamic>) return SqlPlSqlResult.fromJson(plSql);
    return const SqlPlSqlResult(durationMs: 0);
  }

  /// Ejecuta un comando cliente (`data.command`), como `DESC` o `DESCRIBE`.
  Future<SqlCommandResult> executeCommand(
    String commandSql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final cleanSql = stripTrailingSemicolon(commandSql);
    final sw = Stopwatch()..start();
    final data = await _postStatement(
      cleanSql,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      timeoutSegundos: timeoutSegundos,
      client: client,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb (COMMAND)',
      onTrace: onTrace,
    );
    sw.stop();
    final command = data['command'];
    if (command is Map<String, dynamic>) {
      return SqlCommandResult.fromJson(
        command,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    return SqlCommandResult(
      command: cleanSql.trim().split(RegExp(r'\s+')).first.toUpperCase(),
      output: data['message']?.toString() ?? '',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  /// `POST /tools/sql/sessions/{sessionId}/commit` — confirma la
  /// transacción abierta por un DML/DDL/PL-SQL previo.
  Future<void> commitSession(
    String sessionId, {
    required String owner,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) => _sessionAction(
    'commit',
    sessionId,
    owner: owner,
    client: client,
    cancelado: cancelado,
    onTrace: onTrace,
  );

  /// `POST /tools/sql/sessions/{sessionId}/rollback` — descarta la
  /// transacción abierta por un DML/DDL/PL-SQL previo.
  Future<void> rollbackSession(
    String sessionId, {
    required String owner,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) => _sessionAction(
    'rollback',
    sessionId,
    owner: owner,
    client: client,
    cancelado: cancelado,
    onTrace: onTrace,
  );

  Future<void> _sessionAction(
    String action,
    String sessionId, {
    required String owner,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/sessions/$sessionId/$action');
    final traceCb = onTrace ?? onHttpTrace;

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final requestBodyJson = jsonEncode({'owner': owner});

    final trace = SqlHttpTraceEntry(
      id: _httpTraceSeq++,
      timestamp: DateTime.now(),
      method: 'POST',
      url: uri.toString(),
      endpoint: uri.path,
      requestHeaders: headers,
      requestBody: requestBodyJson,
      status: SqlHttpTraceStatus.running,
    );
    traceCb?.call(trace);

    final sw = Stopwatch()..start();
    http.Response response;
    try {
      final httpClient = client ?? _client;
      response = await SirwebService.guardRequest(
        () => httpClient.post(uri, headers: headers, body: requestBodyJson),
        timeout: const Duration(seconds: 30),
        contexto: 'el servidor SirWeb',
        cancelado: cancelado,
      );
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.statusCode = response.statusCode;
    } on SirwebCancelledException {
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.status = SqlHttpTraceStatus.cancelled;
      trace.error = 'Operación cancelada por el usuario';
      traceCb?.call(trace);
      rethrow;
    } catch (e) {
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.status = SqlHttpTraceStatus.error;
      trace.error = e.toString().replaceFirst('Exception: ', '');
      traceCb?.call(trace);
      rethrow;
    }

    final rawBody = utf8.decode(response.bodyBytes);
    trace.responseBody = rawBody;

    final envelope = jsonDecode(rawBody) as Map<String, dynamic>;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['success'] == false) {
      final msg =
          envelope['error']?.toString() ??
          envelope['message']?.toString() ??
          'Error ${response.statusCode} al ejecutar $action';
      trace.status = SqlHttpTraceStatus.error;
      trace.error = msg;
      traceCb?.call(trace);
      throw Exception(msg);
    }

    trace.status = SqlHttpTraceStatus.success;
    traceCb?.call(trace);
  }

  /// Obtiene el plan de ejecución de un SELECT llamando a `POST /tools/sql/explain`.
  Future<SqlExplainResult> explainPlan(
    String sql, {
    required String ambiente,
    String? owner,
    Map<String, dynamic>? binds,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry trace)? onTrace,
  }) async {
    final cleanSql = stripTrailingSemicolon(sql);
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/explain');
    final traceCb = onTrace ?? onHttpTrace;

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final requestBodyJson = jsonEncode({
      'sql': cleanSql,
      'owner': owner ?? '',
      'ambiente': ambiente,
      'binds': binds,
      'timeoutSegundos': timeoutSegundos,
    });

    final trace = SqlHttpTraceEntry(
      id: _httpTraceSeq++,
      timestamp: DateTime.now(),
      method: 'POST',
      url: uri.toString(),
      endpoint: uri.path,
      requestHeaders: headers,
      requestBody: requestBodyJson,
      status: SqlHttpTraceStatus.running,
    );
    traceCb?.call(trace);

    final sw = Stopwatch()..start();
    http.Response response;
    try {
      final httpClient = client ?? _client;
      response = await SirwebService.guardRequest(
        () => httpClient.post(uri, headers: headers, body: requestBodyJson),
        timeout: Duration(seconds: timeoutSegundos + 15),
        contexto: 'el servidor SirWeb (Explain Plan)',
        cancelado: cancelado,
      );
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.statusCode = response.statusCode;
    } on SirwebCancelledException {
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.status = SqlHttpTraceStatus.cancelled;
      trace.error = 'Operación cancelada por el usuario';
      traceCb?.call(trace);
      rethrow;
    } catch (e) {
      sw.stop();
      trace.durationMs = sw.elapsedMilliseconds;
      trace.status = SqlHttpTraceStatus.error;
      trace.error = e.toString().replaceFirst('Exception: ', '');
      traceCb?.call(trace);
      rethrow;
    }

    final rawBody = utf8.decode(response.bodyBytes);
    trace.responseBody = rawBody;

    final envelope = jsonDecode(rawBody) as Map<String, dynamic>;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['success'] == false) {
      final msg =
          envelope['error']?.toString() ??
          envelope['message']?.toString() ??
          'Error ${response.statusCode} al obtener Explain Plan';
      trace.status = SqlHttpTraceStatus.error;
      trace.error = msg;
      traceCb?.call(trace);
      throw Exception(msg);
    }

    trace.status = SqlHttpTraceStatus.success;
    traceCb?.call(trace);

    final data = envelope['data'];
    if (data is Map<String, dynamic>) {
      return SqlExplainResult.fromJson(data);
    }
    return SqlExplainResult(
      ambiente: ambiente,
      rows: const [],
      text: const [],
      tree: const [],
      durationMs: 0,
    );
  }
}
