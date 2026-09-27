/// Orquesta los 4 servicios de ejecución del Ejecutor SQL/PL-SQL: SELECT,
/// DML/DDL, PL/SQL y EXPLAIN PLAN.
///
/// `executeSelect` ya está conectado al backend real (`POST /tools/sql/query`).
/// `executeDml` y `explainPlan` todavía no tienen endpoint: arrojan
/// [SqlServiceNotImplementedException] para que la UI lo muestre como aviso
/// en vez de romperse, hasta que el backend los publique.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ejecucion_procedimiento.dart';
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

  /// `POST /tools/sql/query` — ejecuta un SELECT y devuelve columnas + filas.
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    final host = await SirwebService.getHost();
    final uri = Uri.parse('$host/tools/sql/query');

    final response = await SirwebService.guardRequest(
      () => _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'sql': sql,
          'ambiente': ambiente,
          'maxRows': maxRows,
          'timeoutSegundos': timeoutSegundos,
        }),
      ),
      timeout: Duration(seconds: timeoutSegundos + 15),
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
          'Error ${response.statusCode} al ejecutar la consulta';
      throw Exception(msg);
    }

    final data = envelope['data'];
    if (data is Map<String, dynamic>) return SqlQueryResult.fromJson(data);
    return SqlQueryResult.empty;
  }

  /// Ejecuta DML/DDL. TODO: conectar cuando el backend publique el endpoint
  /// (candidato: `POST /tools/sql/dml`).
  Future<SqlDmlResult> executeDml(
    String sql, {
    required String ambiente,
    int timeoutSegundos = 30,
  }) async {
    throw const SqlServiceNotImplementedException(
      'El servicio de ejecución de DML/DDL todavía está en desarrollo.',
    );
  }

  /// Ejecuta un bloque PL/SQL reutilizando el modo "borrador" ya existente.
  Future<EjecucionResultado> executePlSql(
    String plsqlBlock, {
    required String ambiente,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) {
    return SirwebService().ejecutarBorrador(
      deTexto: plsqlBlock,
      request: EjecucionRequest(
        ambiente: ambiente,
        timeoutSegundos: timeoutSegundos,
      ),
      cancelado: cancelado,
    );
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
