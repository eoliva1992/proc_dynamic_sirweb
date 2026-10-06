/// Orquesta los 4 servicios de ejecución del Ejecutor SQL/PL-SQL: SELECT,
/// DML/DDL, PL/SQL y EXPLAIN PLAN.
///
/// `executeSelect`, `executeDml`, `executeDdl` y `executePlSql` comparten
/// `POST /tools/sql/statement`: se ejecutan siempre con `confirmar: false`
/// (sin auto-commit), dejando la transacción abierta bajo un `sessionId`
/// hasta que se llame a `commitSession`/`rollbackSession`. El backend exige
/// `owner` no vacío (el `cdUsuario` configurado en la app).
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sql_execution.dart';
import 'sirweb_service.dart';

/// Señal de que el servicio todavía no está implementado en el backend.
class SqlServiceNotImplementedException implements Exception {
  const SqlServiceNotImplementedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SqlExecutorService {
  static final SqlExecutorService _instance = SqlExecutorService._();
  factory SqlExecutorService() => _instance;
  SqlExecutorService._();

  static final http.Client _client = http.Client();

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
    bool Function()? cancelado,
    required String contexto,
  }) async {
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/statement');

    final response = await SirwebService.guardRequest(
      () => _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // Los campos no usados se omiten (no se mandan como `null`): el
        // backend puede tener tipos no-nullable (p.ej. int) para algunos de
        // estos parámetros opcionales y rechaza un JSON null explícito.
        body: jsonEncode({
          'owner': owner,
          'sql': sql,
          'ambiente': ambiente,
          'confirmar': confirmar,
          'maxRows': maxRows,
          'timeoutSegundos': timeoutSegundos,
          'capturarDbmsOutput': capturarDbmsOutput,
          if (sessionId != null) 'sessionId': sessionId,
          if (binds != null) 'binds': binds,
          if (maxRowsAffected != null) 'maxRowsAffected': maxRowsAffected,
          if (objectName != null) 'objectName': objectName,
          if (objectType != null) 'objectType': objectType,
          if (plSqlBinds != null) 'plSqlBinds': plSqlBinds,
        }),
      ),
      timeout: Duration(seconds: timeoutSegundos + 15),
      contexto: contexto,
      cancelado: cancelado,
    );

    final rawBody = utf8.decode(response.bodyBytes);
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(rawBody) as Map<String, dynamic>;
    } on FormatException {
      // El backend devolvió texto plano (p.ej. un error de ASP.NET Core)
      // en vez del sobre JSON esperado; mostramos ese texto tal cual.
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
      throw Exception(msg);
    }

    return envelope['data'] as Map<String, dynamic>? ?? const {};
  }

  /// Ejecuta un SELECT y devuelve columnas + filas (`data.query`).
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    final data = await _postStatement(
      sql,
      ambiente: ambiente,
      owner: owner,
      maxRows: maxRows,
      timeoutSegundos: timeoutSegundos,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb',
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
    bool Function()? cancelado,
  }) async {
    final data = await _postStatement(
      sql,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      maxRowsAffected: maxRows,
      maxRows: maxRows,
      timeoutSegundos: timeoutSegundos,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb',
    );
    final dml = data['dml'];
    if (dml is Map<String, dynamic>) return SqlDmlResult.fromJson(dml);
    return const SqlDmlResult(rowsAffected: 0, durationMs: 0);
  }

  /// Ejecuta un DDL (`data.ddl`): el backend no abre sesión para DDL (es
  /// auto-commit en Oracle), por eso no hay `sessionId`/`pendingCommit` aquí.
  Future<SqlDdlResult> executeDdl(
    String sql, {
    required String ambiente,
    required String owner,
    String? objectName,
    String? objectType,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    final data = await _postStatement(
      sql,
      ambiente: ambiente,
      owner: owner,
      objectName: objectName,
      objectType: objectType,
      timeoutSegundos: timeoutSegundos,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb',
    );
    final ddl = data['ddl'];
    if (ddl is Map<String, dynamic>) return SqlDdlResult.fromJson(ddl);
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
    bool Function()? cancelado,
  }) async {
    final data = await _postStatement(
      plsqlBlock,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      capturarDbmsOutput: true,
      timeoutSegundos: timeoutSegundos,
      cancelado: cancelado,
      contexto: 'el servidor SirWeb (PL/SQL)',
    );
    final plSql = data['plSql'];
    if (plSql is Map<String, dynamic>) return SqlPlSqlResult.fromJson(plSql);
    return const SqlPlSqlResult(durationMs: 0);
  }

  /// `POST /tools/sql/sessions/{sessionId}/commit` — confirma la
  /// transacción abierta por un DML/DDL/PL-SQL previo.
  Future<void> commitSession(
    String sessionId, {
    required String owner,
    bool Function()? cancelado,
  }) => _sessionAction('commit', sessionId, owner: owner, cancelado: cancelado);

  /// `POST /tools/sql/sessions/{sessionId}/rollback` — descarta la
  /// transacción abierta por un DML/DDL/PL-SQL previo.
  Future<void> rollbackSession(
    String sessionId, {
    required String owner,
    bool Function()? cancelado,
  }) =>
      _sessionAction('rollback', sessionId, owner: owner, cancelado: cancelado);

  Future<void> _sessionAction(
    String action,
    String sessionId, {
    required String owner,
    bool Function()? cancelado,
  }) async {
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/sessions/$sessionId/$action');

    final response = await SirwebService.guardRequest(
      () => _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'owner': owner}),
      ),
      timeout: const Duration(seconds: 30),
      contexto: 'el servidor SirWeb',
      cancelado: cancelado,
    );

    final envelope =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['success'] == false) {
      final msg =
          envelope['error']?.toString() ??
          envelope['message']?.toString() ??
          'Error ${response.statusCode} al ejecutar $action';
      throw Exception(msg);
    }
  }

  /// Obtiene el plan de ejecución de un SELECT llamando a `POST /tools/sql/explain`.
  Future<SqlExplainResult> explainPlan(
    String sql, {
    required String ambiente,
    String? owner,
    Map<String, dynamic>? binds,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/explain');

    final response = await SirwebService.guardRequest(
      () => _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'sql': sql,
          'owner': owner ?? '',
          'ambiente': ambiente,
          'binds': binds,
          'timeoutSegundos': timeoutSegundos,
        }),
      ),
      timeout: Duration(seconds: timeoutSegundos + 15),
      contexto: 'el servidor SirWeb (Explain Plan)',
      cancelado: cancelado,
    );

    final envelope =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['success'] == false) {
      final msg =
          envelope['error']?.toString() ??
          envelope['message']?.toString() ??
          'Error ${response.statusCode} al obtener Explain Plan';
      throw Exception(msg);
    }

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
