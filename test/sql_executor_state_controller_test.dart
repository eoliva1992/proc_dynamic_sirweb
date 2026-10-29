import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/models/sql_http_trace.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/services/sirweb_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_state_controller.dart';
import 'package:proc_dynamic_sirweb/services/sql_session_manager.dart';

class _FakeSqlExecutorService implements SqlExecutorService {
  @override
  void Function(SqlHttpTraceEntry)? onHttpTrace;

  int selectCalls = 0;
  int dmlCalls = 0;
  int ddlCalls = 0;
  List<SqlDdlError> ddlErrorsToReturn = const [];
  int commitCalls = 0;
  int rollbackCalls = 0;
  String? lastSql;
  String? lastSessionId;
  String? lastOwner;
  int? lastSelectMaxRows;
  int? lastDmlMaxRows;
  String? dmlSessionIdToReturn;
  SqlQueryResult? selectResultToReturn;
  void Function(String? sessionId)? onExecuteSelect;
  void Function(String? sessionId)? onExecuteDml;
  void Function(String sessionId)? onCommit;
  void Function(String sessionId)? onRollback;

  @override
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    selectCalls++;
    lastSql = sql;
    lastOwner = owner;
    lastSessionId = sessionId;
    lastSelectMaxRows = maxRows;
    onExecuteSelect?.call(sessionId);
    return selectResultToReturn ??
        const SqlQueryResult(
          columns: [
            SqlColumn(name: 'ID', dataType: 'NUMBER'),
            SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
          ],
          rows: [
            [1, 'TEST'],
          ],
          returnedRows: 1,
          truncated: false,
          durationMs: 42,
        );
  }

  @override
  Future<SqlDmlResult> executeDml(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    dmlCalls++;
    lastSql = sql;
    lastSessionId = sessionId;
    lastOwner = owner;
    lastDmlMaxRows = maxRows;
    onExecuteDml?.call(sessionId);
    return SqlDmlResult(
      rowsAffected: 3,
      durationMs: 15,
      message: '3 filas actualizadas',
      sessionId: dmlSessionIdToReturn,
    );
  }

  @override
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
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    ddlCalls++;
    lastSql = sql;
    lastOwner = owner;
    lastSessionId = sessionId;
    return SqlDdlResult(
      ambiente: 'Desa',
      confirmed: true,
      autoCommitPossible: true,
      errors: ddlErrorsToReturn,
      durationMs: 10,
    );
  }

  @override
  Future<SqlPlSqlResult> executePlSql(
    String plsql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    lastSql = plsql;
    lastSessionId = sessionId;
    lastOwner = owner;
    return const SqlPlSqlResult(durationMs: 5);
  }

  @override
  Future<SqlCommandResult> executeCommand(
    String commandSql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    lastSql = commandSql;
    lastOwner = owner;
    lastSessionId = sessionId;
    return SqlCommandResult(
      command: commandSql.trim().split(RegExp(r'\s+')).first.toUpperCase(),
      output: 'OK',
      durationMs: 2,
    );
  }

  @override
  Future<void> commitSession(
    String sessionId, {
    required String owner,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    commitCalls++;
    lastSessionId = sessionId;
    lastOwner = owner;
    onCommit?.call(sessionId);
  }

  @override
  Future<void> rollbackSession(
    String sessionId, {
    required String owner,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    rollbackCalls++;
    lastSessionId = sessionId;
    lastOwner = owner;
    onRollback?.call(sessionId);
  }

  @override
  Future<SqlExplainResult> explainPlan(
    String sql, {
    required String ambiente,
    String? owner,
    Map<String, dynamic>? binds,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    return const SqlExplainResult(
      ambiente: 'Desa',
      rows: [
        SqlExplainPlanNode(
          id: 1,
          operation: 'SELECT STATEMENT',
          depth: 0,
          cost: 3,
        ),
        SqlExplainPlanNode(
          id: 2,
          parentId: 1,
          operation: 'TABLE ACCESS',
          options: 'FULL',
          objectName: 'EMPLEADOS',
          depth: 1,
          cost: 3,
        ),
      ],
      text: ['Plan hash value: 123456789', '| Id | Operation | Name | Cost |'],
      tree: [],
      durationMs: 8,
    );
  }
}

class _CancellableFakeSqlExecutorService extends _FakeSqlExecutorService {
  final Completer<void> started = Completer<void>();
  final Completer<SqlQueryResult> completer;

  _CancellableFakeSqlExecutorService(this.completer);

  @override
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    selectCalls++;
    if (!started.isCompleted) started.complete();
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (cancelado?.call() ?? false) {
          throw const SirwebCancelledException();
        }
        throw Exception('Timeout');
      },
    );
  }
}

class _BatchCancellableFakeSqlExecutorService extends _FakeSqlExecutorService {
  final List<String> executed;
  void Function(String sql)? onSelect;

  _BatchCancellableFakeSqlExecutorService(this.executed);

  @override
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    executed.add(sql);
    onSelect?.call(sql);
    if (cancelado?.call() ?? false) {
      throw const SirwebCancelledException();
    }
    return super.executeSelect(
      sql,
      ambiente: ambiente,
      owner: owner,
      sessionId: sessionId,
      maxRows: maxRows,
      timeoutSegundos: timeoutSegundos,
      client: client,
      cancelado: cancelado,
      onTrace: onTrace,
    );
  }
}

void main() {
  group('SqlExecutorStateController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SqlSessionManager.instance.reset();
      // El backend exige 'owner' (cdUsuario) no vacío en /tools/sql/statement.
      procedimientosProvider.setCdUsuario('TESTUSER');
    });

    test('inicializa con estado esperado', () {
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'QA',
        initialSql: 'SELECT * FROM DUAL;',
      );
      addTearDown(ctrl.dispose);

      expect(ctrl.ambiente, 'QA');
      expect(ctrl.text, 'SELECT * FROM DUAL;');
      expect(ctrl.cursorLine, 1);
      expect(ctrl.cursorCol, 1);
      expect(ctrl.running, isFalse);
      expect(ctrl.resultsPanelVisible, isTrue);
      expect(ctrl.currentStatement()?.text.trim(), 'SELECT * FROM DUAL;');
    });

    test('actualiza cursor y texto notificando oyentes', () {
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT 1 FROM dual;\nSELECT 2 FROM dual;',
      );
      addTearDown(ctrl.dispose);

      var notifications = 0;
      ctrl.addListener(() => notifications++);

      ctrl.setCursor(2, 5);
      expect(ctrl.cursorLine, 2);
      expect(ctrl.cursorCol, 5);
      expect(notifications, 1);

      final stmt = ctrl.currentStatement();
      expect(stmt?.text.trim(), 'SELECT 2 FROM dual;');

      ctrl.setText('SELECT 99 FROM dual;');
      expect(ctrl.text, 'SELECT 99 FROM dual;');
      expect(notifications, 2);
    });

    test(
      'runCurrentOrSelection ejecuta SELECT correctamente con servicio mock',
      () async {
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT ID, NAME FROM EMPLEADOS;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        var tabIndex = -1;
        ctrl.onTabChangeRequested = (idx) => tabIndex = idx;

        await ctrl.runCurrentOrSelection();

        expect(fakeSvc.selectCalls, 1);
        expect(fakeSvc.lastSql?.trim(), 'SELECT ID, NAME FROM EMPLEADOS;');
        expect(ctrl.lastResult, isNotNull);
        expect(ctrl.lastResult!.returnedRows, 1);
        expect(ctrl.log.length, 1);
        expect(ctrl.log.first.status, SqlLogStatus.success);
        expect(tabIndex, 0); // Pestaña 'Resultados'
      },
    );

    test(
      'runCurrentOrSelection ejecuta DDL con errores y reporta SqlLogStatus.error y onDdlCompilationErrors',
      () async {
        final fakeSvc = _FakeSqlExecutorService();
        fakeSvc.ddlErrorsToReturn = [
          const SqlDdlError(
            line: 5,
            position: 10,
            text: 'PLS-00103: Encountered the symbol "X"',
          ),
        ];
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'CREATE OR REPLACE PROCEDURE pr_test AS BEGIN NULL; END;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        List<SqlDdlError>? reportedErrors;
        ctrl.onDdlCompilationErrors = (stmt, errors) => reportedErrors = errors;

        await ctrl.runCurrentOrSelection();

        expect(fakeSvc.ddlCalls, 1);
        expect(ctrl.log.length, 1);
        expect(ctrl.log.first.status, SqlLogStatus.error);
        expect(ctrl.log.first.message, contains('PLS-00103'));
        expect(reportedErrors, isNotNull);
        expect(reportedErrors, hasLength(1));
        expect(reportedErrors!.first.line, 5);
      },
    );

    test('runCurrentOrSelection ejecuta sólo el texto seleccionado, ignorando '
        'el resto del editor', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql:
            'SELECT 1 FROM dual;\nSELECT ID, NAME FROM EMPLEADOS;\nSELECT 3 FROM dual;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);
      ctrl.getSelectedText = () async => 'SELECT ID, NAME FROM EMPLEADOS';

      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 1);
      expect(fakeSvc.lastSql, 'SELECT ID, NAME FROM EMPLEADOS');
    });

    test('runCurrentOrSelection recurre a la sentencia del cursor cuando no '
        'hay selección', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT ID, NAME FROM EMPLEADOS;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);
      ctrl.getSelectedText = () async => '   ';

      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 1);
      expect(fakeSvc.lastSql?.trim(), 'SELECT ID, NAME FROM EMPLEADOS;');
    });

    test('runCurrentOrSelection ejecuta una selección sin ";" final', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT ID, NAME FROM EMPLEADOS',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);
      ctrl.getSelectedText = () async => 'SELECT ID, NAME FROM EMPLEADOS';

      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 1);
      expect(fakeSvc.lastSql, 'SELECT ID, NAME FROM EMPLEADOS');
      expect(ctrl.log.first.status, SqlLogStatus.success);
    });

    test('runCurrentOrSelection ejecuta varias sentencias seleccionadas y '
        'produce un resultado por cada una', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: '',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);
      ctrl.getSelectedText = () async =>
          'SELECT 1 FROM dual;\nUPDATE CLIENTES SET ACTIVO = 1;';

      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 1);
      expect(fakeSvc.dmlCalls, 1);
      expect(ctrl.log.length, 2);
      expect(ctrl.log[0].status, SqlLogStatus.success);
      expect(ctrl.log[1].status, SqlLogStatus.success);
    });

    test('runAll ejecuta múltiples sentencias secuencialmente', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT 1 FROM dual;\nUPDATE CLIENTES SET ACTIVO = 1;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);

      await ctrl.runAll();

      expect(fakeSvc.selectCalls, 1);
      expect(fakeSvc.dmlCalls, 1);
      expect(ctrl.log.length, 2);
      expect(ctrl.log.first.status, SqlLogStatus.success);
      expect(ctrl.log.last.status, SqlLogStatus.success);
    });

    test('runExplainPlan obtiene y almacena el plan de ejecución', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT * FROM EMPLEADOS;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);

      var tabIndex = -1;
      ctrl.onTabChangeRequested = (idx) => tabIndex = idx;

      await ctrl.runExplainPlan();

      expect(ctrl.explainNodes, isNotNull);
      expect(ctrl.explainNodes!.length, 2);
      expect(ctrl.lastExplainResult, isNotNull);
      expect(ctrl.lastExplainResult!.text.length, 2);
      expect(ctrl.log.length, 1);
      expect(ctrl.log.first.kind, SqlStatementKind.explainPlan);
      expect(ctrl.log.first.status, SqlLogStatus.success);
      expect(tabIndex, 2); // Pestaña 'Plan de Ejecución'
    });

    test('clearOutput vacía log y resultados', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT 1 FROM dual;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);

      await ctrl.runCurrentOrSelection();
      expect(ctrl.log.length, 1);
      expect(ctrl.lastResult, isNotNull);

      ctrl.clearOutput();
      expect(ctrl.log, isEmpty);
      expect(ctrl.lastResult, isNull);
      expect(ctrl.explainNodes, isNull);
    });

    test('ejecutar varios SELECT genera un resultado por cada uno en la corrida '
        'y una nueva corrida limpia los tabs anteriores', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: '',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);
      ctrl.getSelectedText = () async =>
          'SELECT 1 FROM dual;\nSELECT 2 FROM dual;';

      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 2);
      expect(ctrl.results.length, 2);
      expect(ctrl.results[0].statementText, 'SELECT 1 FROM dual;');
      expect(ctrl.results[1].statementText, 'SELECT 2 FROM dual;');
      expect(ctrl.selectedResultIndex, 1);
      expect(ctrl.lastResult, same(ctrl.results[1].result));

      ctrl.selectResult(0);
      expect(ctrl.selectedResultIndex, 0);
      expect(ctrl.lastResult, same(ctrl.results[0].result));

      // Nueva corrida con 1 sola consulta: debe limpiar los tabs viejos y dejar solo 1
      ctrl.getSelectedText = () async => 'SELECT 3 FROM dual;';
      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 3);
      expect(ctrl.results.length, 1);
      expect(ctrl.results[0].statementText, 'SELECT 3 FROM dual;');
      expect(ctrl.selectedResultIndex, 0);

      ctrl.clearOutput();
      expect(ctrl.results, isEmpty);
      expect(ctrl.selectedResultIndex, 0);
    });

    test(
      'persiste historial en SharedPreferences y respeta retención de 7 días',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        await ctrl.runCurrentOrSelection();
        expect(ctrl.log.length, 1);

        // Esperar brevemente a que el guardado asíncrono complete
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final prefs = await SharedPreferences.getInstance();
        final savedJson = prefs.getString('sql_executor_log_history_v1');
        expect(savedJson, isNotNull);
        expect(savedJson, contains('SELECT 1'));

        // Crear un nuevo controller simulando inicio de la app posterior
        final ctrl2 = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: '',
          service: fakeSvc,
        );
        addTearDown(ctrl2.dispose);

        // Esperar a que _loadPersistedLog complete
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(ctrl2.log.length, 1);
        expect(ctrl2.log.first.statementPreview, contains('SELECT 1'));
      },
    );

    test(
      'recibe y acumula trazas HTTP en httpTraces y las limpia con clearHttpTraces',
      () {
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.httpTraces, isEmpty);

        // Simula evento emitido por onHttpTrace
        final trace1 = SqlHttpTraceEntry(
          id: 1,
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'http://localhost:5000/tools/sql/statement',
          endpoint: '/tools/sql/statement',
          requestBody: '{"sql":"SELECT 1 FROM dual"}',
          status: SqlHttpTraceStatus.running,
        );
        fakeSvc.onHttpTrace?.call(trace1);

        expect(ctrl.httpTraces.length, 1);
        expect(ctrl.httpTraces.first.status, SqlHttpTraceStatus.running);

        // Actualización de la misma traza al completarse
        trace1.statusCode = 200;
        trace1.status = SqlHttpTraceStatus.success;
        trace1.responseBody = '{"success":true}';
        fakeSvc.onHttpTrace?.call(trace1);

        expect(ctrl.httpTraces.length, 1);
        expect(ctrl.httpTraces.first.statusCode, 200);
        expect(ctrl.httpTraces.first.status, SqlHttpTraceStatus.success);

        ctrl.clearHttpTraces();
        expect(ctrl.httpTraces, isEmpty);
      },
    );

    test(
      'al llamar dispose() desregistra el callback onHttpTrace y no falla si se emite traza posterior',
      () {
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
          service: fakeSvc,
        );

        expect(fakeSvc.onHttpTrace, isNotNull);
        final callback = fakeSvc.onHttpTrace;

        ctrl.dispose();

        expect(fakeSvc.onHttpTrace, isNull);

        // Si por alguna razón una referencia vieja al callback fuera invocada,
        // no debe lanzar excepción de ChangeNotifier usado post-dispose.
        final trace = SqlHttpTraceEntry(
          id: 99,
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'http://localhost:5000/tools/sql/statement',
          endpoint: '/tools/sql/statement',
          requestBody: '{"sql":"SELECT 1 FROM dual"}',
          status: SqlHttpTraceStatus.running,
        );
        expect(() => callback?.call(trace), returnsNormally);
      },
    );

    test(
      'ejecutar un DML abre sesión y commit() la confirma manteniendo la sesión viva',
      () async {
        final fakeSvc = _FakeSqlExecutorService()
          ..dmlSessionIdToReturn = 'sess-1';
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'UPDATE CLIENTES SET ACTIVO = 1;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        await ctrl.runCurrentOrSelection();
        expect(ctrl.hasPendingChanges, isTrue);
        expect(ctrl.sessionId, 'sess-1');

        await ctrl.commit();
        expect(fakeSvc.commitCalls, 1);
        expect(fakeSvc.lastSessionId, 'sess-1');
        // Tras commit, los cambios pendientes quedan limpios pero el sessionId NO se borra
        expect(ctrl.hasPendingChanges, isFalse);
        expect(ctrl.sessionId, 'sess-1');
        expect(ctrl.log.last.message, contains('confirmados'));
      },
    );

    test(
      'rollback() descarta cambios pendientes manteniendo la sesión viva',
      () async {
        final fakeSvc = _FakeSqlExecutorService()
          ..dmlSessionIdToReturn = 'sess-2';
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'UPDATE CLIENTES SET ACTIVO = 1;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        await ctrl.runCurrentOrSelection();
        await ctrl.rollback();

        expect(fakeSvc.rollbackCalls, 1);
        expect(fakeSvc.lastSessionId, 'sess-2');
        expect(ctrl.hasPendingChanges, isFalse);
        expect(ctrl.sessionId, 'sess-2');
      },
    );

    test(
      'cambiar de ambiente descarta la sesión pendiente localmente',
      () async {
        final fakeSvc = _FakeSqlExecutorService()
          ..dmlSessionIdToReturn = 'sess-3';
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'UPDATE CLIENTES SET ACTIVO = 1;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        await ctrl.runCurrentOrSelection();
        expect(ctrl.hasPendingChanges, isTrue);

        ctrl.setAmbiente('QA');
        expect(ctrl.hasPendingChanges, isFalse);
      },
    );

    test(
      'dos pestañas en el mismo ambiente comparten la sesión de transacción abierta (DML + SELECT)',
      () async {
        final fakeSvc = _FakeSqlExecutorService()
          ..dmlSessionIdToReturn = 'session-compartida-123';

        // Pestaña 1 (ejecuta INSERT/UPDATE)
        final tab1 = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'INSERT INTO TEST_TABLE VALUES (1, "A");',
          service: fakeSvc,
        );
        addTearDown(tab1.dispose);

        // Pestaña 2 (abierta con la misma conexión / ambiente)
        final tab2 = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT * FROM TEST_TABLE;',
          service: fakeSvc,
        );
        addTearDown(tab2.dispose);

        // Al inicio, ninguna tiene sesión abierta
        expect(tab1.hasPendingChanges, isFalse);
        expect(tab2.hasPendingChanges, isFalse);

        // Pestaña 1 ejecuta DML sin commit
        await tab1.runCurrentOrSelection();

        expect(tab1.hasPendingChanges, isTrue);
        expect(tab1.sessionId, 'session-compartida-123');

        // Pestaña 2 detecta de inmediato la transacción pendiente gracias a SqlSessionManager
        expect(tab2.hasPendingChanges, isTrue);
        expect(tab2.sessionId, 'session-compartida-123');

        // Pestaña 2 ejecuta SELECT: debe enviar el sessionId de la transacción
        await tab2.runCurrentOrSelection();
        expect(fakeSvc.selectCalls, 1);
        expect(fakeSvc.lastSessionId, 'session-compartida-123');

        // Pestaña 2 hace COMMIT
        await tab2.commit();
        expect(fakeSvc.commitCalls, 1);
        expect(fakeSvc.lastSessionId, 'session-compartida-123');

        // Ambas pestañas quedan limpias sin cambios pendientes, pero la sesión permanece viva
        expect(tab1.hasPendingChanges, isFalse);
        expect(tab2.hasPendingChanges, isFalse);
        expect(tab1.sessionId, 'session-compartida-123');
        expect(tab2.sessionId, 'session-compartida-123');
      },
    );

    test(
      'pestañas en ambientes diferentes mantienen sesiones aisladas e independientes',
      () async {
        final fakeSvc = _FakeSqlExecutorService()
          ..dmlSessionIdToReturn = 'session-desa-999';

        final tabDesa = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'UPDATE TEST_TABLE SET A = 2;',
          service: fakeSvc,
        );
        addTearDown(tabDesa.dispose);

        final tabQa = SqlExecutorStateController(
          initialAmbiente: 'QA',
          initialSql: 'SELECT * FROM TEST_TABLE;',
          service: fakeSvc,
        );
        addTearDown(tabQa.dispose);

        await tabDesa.runCurrentOrSelection();
        expect(tabDesa.hasPendingChanges, isTrue);
        expect(tabDesa.sessionId, 'session-desa-999');

        // QA no debe ser afectado por la sesión de Desa
        expect(tabQa.hasPendingChanges, isFalse);
        expect(tabQa.sessionId, isNull);

        await tabQa.runCurrentOrSelection();
        expect(fakeSvc.lastSessionId, isNull);
      },
    );

    test('envía el cdUsuario configurado como owner al ejecutar', () async {
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT * FROM DUAL;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);

      await ctrl.runCurrentOrSelection();

      expect(fakeSvc.selectCalls, 1);
      expect(fakeSvc.lastOwner, 'TESTUSER');
    });

    test(
      'si no hay cdUsuario y ensureUsuario cancela, no se ejecuta la sentencia',
      () async {
        procedimientosProvider.setCdUsuario('');
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT * FROM DUAL;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);
        ctrl.ensureUsuario = () async => false;

        await ctrl.runCurrentOrSelection();

        expect(fakeSvc.selectCalls, 0);
      },
    );

    test(
      'si no hay cdUsuario pero ensureUsuario lo configura, la sentencia se ejecuta',
      () async {
        procedimientosProvider.setCdUsuario('');
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT * FROM DUAL;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);
        ctrl.ensureUsuario = () async {
          procedimientosProvider.setCdUsuario('NUEVOUSUARIO');
          return true;
        };

        await ctrl.runCurrentOrSelection();

        expect(fakeSvc.selectCalls, 1);
        expect(fakeSvc.lastOwner, 'NUEVOUSUARIO');
      },
    );

    test(
      'setMaxRows(-1) permite modo sin límite y lo propaga a executeSelect y executeDml',
      () async {
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT * FROM DUAL;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.maxRows, 1000);

        await ctrl.setMaxRows(-1);
        expect(ctrl.maxRows, -1);

        await ctrl.runCurrentOrSelection();
        expect(fakeSvc.selectCalls, 1);
        expect(fakeSvc.lastSelectMaxRows, -1);

        ctrl.setText('UPDATE CLIENTES SET ACTIVO = 1;');
        await ctrl.runCurrentOrSelection();
        expect(fakeSvc.dmlCalls, 1);
        expect(fakeSvc.lastDmlMaxRows, -1);
      },
    );

    test(
      'cambiar de ambiente reutiliza la sesión si ya existía para ese ambiente y dueño',
      () async {
        final fakeSvc = _FakeSqlExecutorService();

        // 1. Simular que previamente en QA se generó una sesión
        SqlSessionManager.instance.setSessionId(
          'QA',
          'sess-qa-existente',
          owner: 'TESTUSER',
        );

        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM DUAL;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.sessionId, isNull);

        // 2. Cambiar de ambiente a QA
        ctrl.setAmbiente('QA');

        // 3. Debe adoptar inmediatamente la sesión ya existente de QA sin crear otra
        expect(ctrl.sessionId, 'sess-qa-existente');

        // 4. Ejecutar sentencia: envía la sesión existente
        await ctrl.runCurrentOrSelection();
        expect(fakeSvc.lastSessionId, 'sess-qa-existente');
      },
    );

    test(
      'cambiar de usuario (owner) alterna la sesión al par correspondiente',
      () async {
        final fakeSvc = _FakeSqlExecutorService();

        SqlSessionManager.instance.setSessionId(
          'Desa',
          'sess-user-a',
          owner: 'USER_A',
        );
        SqlSessionManager.instance.setSessionId(
          'Desa',
          'sess-user-b',
          owner: 'USER_B',
        );

        procedimientosProvider.setCdUsuario('USER_A');

        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM DUAL;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.sessionId, 'sess-user-a');

        // Cambiar de usuario
        procedimientosProvider.setCdUsuario('USER_B');

        expect(ctrl.sessionId, 'sess-user-b');
      },
    );

    test('persistencia de maxRows en SharedPreferences admite -1', () async {
      SharedPreferences.setMockInitialValues({'sql_executor_max_rows': -1});
      final fakeSvc = _FakeSqlExecutorService();
      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT 1 FROM dual;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);

      // Esperar a que _loadMaxRowsPreference complete
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ctrl.maxRows, -1);
    });

    test(
      'permite alternar desacople y fijación (pin) del panel de resultados',
      () {
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.resultsPanelDetached, isFalse);
        expect(ctrl.resultsPanelPinned, isTrue);

        ctrl.toggleResultsPanelDetached();
        expect(ctrl.resultsPanelDetached, isTrue);

        ctrl.setResultsPanelDetached(false);
        expect(ctrl.resultsPanelDetached, isFalse);

        ctrl.toggleResultsPanelPinned();
        expect(ctrl.resultsPanelPinned, isFalse);

        ctrl.setResultsPanelPinned(true);
        expect(ctrl.resultsPanelPinned, isTrue);
      },
    );

    test(
      'cancel() detiene una ejecución en curso y registra advertencia en el log',
      () async {
        final completer = Completer<SqlQueryResult>();
        final cancellableSvc = _CancellableFakeSqlExecutorService(completer);
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT * FROM big_table;',
          service: cancellableSvc,
        );
        addTearDown(ctrl.dispose);

        // Inicia ejecución asíncrona
        final runFuture = ctrl.runCurrentOrSelection();
        await cancellableSvc.started.future;
        expect(ctrl.running, isTrue);

        // Cancela mientras está corriendo
        ctrl.cancel();
        expect(ctrl.cancelRequested, isTrue);

        await runFuture;
        expect(ctrl.running, isFalse);
        expect(ctrl.log, isNotEmpty);
        expect(ctrl.log.last.status, SqlLogStatus.warning);
        expect(ctrl.log.last.message, contains('cancelada por el usuario'));
      },
    );

    test(
      'cancel() durante runAll() aborta el lote y no ejecuta sentencias siguientes',
      () async {
        final executed = <String>[];
        final stepSvc = _BatchCancellableFakeSqlExecutorService(executed);
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql:
              'SELECT 1 FROM dual;\nSELECT 2 FROM dual;\nSELECT 3 FROM dual;',
          service: stepSvc,
        );
        addTearDown(ctrl.dispose);

        stepSvc.onSelect = (sql) {
          if (sql.contains('1')) {
            ctrl.cancel();
          }
        };

        await ctrl.runAll();
        expect(ctrl.running, isFalse);
        expect(executed.length, 1);
        expect(executed.first, contains('SELECT 1'));
      },
    );

    test(
      'clearLog() vacía solo el log sin borrar los resultados de queries',
      () async {
        final fakeSvc = _FakeSqlExecutorService();
        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        await ctrl.runCurrentOrSelection();
        expect(ctrl.log, isNotEmpty);
        expect(ctrl.results, isNotEmpty);

        ctrl.clearLog();
        expect(ctrl.log, isEmpty);
        expect(ctrl.results, isNotEmpty);
      },
    );

    test(
      'reintenta automáticamente y obtiene nueva sesión si la sesión SQL expiró en el servidor',
      () async {
        final fakeSvc = _FakeSqlExecutorService();

        // Inicializamos con una sesión existente en el gestor (simulando una sesión vieja/expirada)
        SqlSessionManager.instance.setSessionId(
          'Desa',
          'sess-expirada-123',
          owner: 'TESTUSER',
        );

        var firstCall = true;
        fakeSvc.onExecuteSelect = (sessionId) {
          if (firstCall) {
            firstCall = false;
            expect(sessionId, 'sess-expirada-123');
            throw Exception(
              'Error en EjecutarSentencia: La sesión SQL no existe o expiró.',
            );
          }
          // En el reintento, la sesión debe haberse limpiado (null)
          expect(sessionId, isNull);
        };

        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.sessionId, 'sess-expirada-123');

        // Ejecutar sentencia
        await ctrl.runCurrentOrSelection();

        // La ejecución debió reintentarse y terminar en éxito
        expect(fakeSvc.selectCalls, 2);
        expect(ctrl.log.last.status, SqlLogStatus.success);
        expect(ctrl.log.last.message, 'OK');
        expect(ctrl.results.length, 1);
        expect(ctrl.sessionId, isNull);
      },
    );

    test(
      'reintenta automáticamente y abre nueva sesión ante error ORA-12570 de red/desconexión',
      () async {
        final fakeSvc = _FakeSqlExecutorService();

        SqlSessionManager.instance.setSessionId(
          'Desa',
          'sess-cortada-555',
          owner: 'TESTUSER',
        );

        var firstCall = true;
        fakeSvc.onExecuteSelect = (sessionId) {
          if (firstCall) {
            firstCall = false;
            expect(sessionId, 'sess-cortada-555');
            throw Exception(
              'Error de Oracle al ejecutar la sentencia: ORA-12570: Sesión de Red: error de lectura de paquete inesperado',
            );
          }
          expect(sessionId, isNull);
        };

        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT * FROM DUAL;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.sessionId, 'sess-cortada-555');

        await ctrl.runCurrentOrSelection();

        expect(fakeSvc.selectCalls, 2);
        expect(ctrl.log.last.status, SqlLogStatus.success);
        expect(ctrl.log.last.message, 'OK');
        expect(ctrl.results.length, 1);
        expect(ctrl.sessionId, isNull);
      },
    );

    test(
      'en DML con sesión expirada, reintenta con sessionId null y asigna el nuevo sessionId devuelto',
      () async {
        final fakeSvc = _FakeSqlExecutorService();

        SqlSessionManager.instance.setSessionId(
          'Desa',
          'sess-vieja-456',
          owner: 'TESTUSER',
        );

        var firstDml = true;
        fakeSvc.onExecuteDml = (sessionId) {
          if (firstDml) {
            firstDml = false;
            expect(sessionId, 'sess-vieja-456');
            throw Exception('La sesión SQL no existe o expiró.');
          }
          expect(sessionId, isNull);
          fakeSvc.dmlSessionIdToReturn = 'sess-nueva-789';
        };

        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'UPDATE CLIENTES SET ACTIVO = 1;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.sessionId, 'sess-vieja-456');

        await ctrl.runCurrentOrSelection();

        expect(fakeSvc.dmlCalls, 2);
        expect(ctrl.log.last.status, SqlLogStatus.success);
        expect(ctrl.sessionId, 'sess-nueva-789');
        expect(ctrl.hasPendingChanges, isTrue);
      },
    );

    test(
      'commit() con sesión expirada en servidor limpia la sesión y muestra advertencia sin error',
      () async {
        final fakeSvc = _FakeSqlExecutorService();

        SqlSessionManager.instance.setSessionId(
          'Desa',
          'sess-vencida-999',
          owner: 'TESTUSER',
          hasPendingChanges: true,
        );

        fakeSvc.onCommit = (sessionId) {
          throw Exception('La sesión SQL no existe o expiró.');
        };

        final ctrl = SqlExecutorStateController(
          initialAmbiente: 'Desa',
          initialSql: 'SELECT 1 FROM dual;',
          service: fakeSvc,
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.hasPendingChanges, isTrue);

        await ctrl.commit();

        expect(ctrl.hasPendingChanges, isFalse);
        expect(ctrl.sessionId, isNull);
        expect(ctrl.log.last.status, SqlLogStatus.warning);
        expect(
          ctrl.log.last.message,
          contains('La sesión expiró o ya no existe'),
        );
      },
    );

    test('loadMoreRows pagina y anexa filas al resultado truncado', () async {
      final fakeSvc = _FakeSqlExecutorService();
      // 1. La primera consulta devuelve resultado truncado con 2 filas
      fakeSvc.selectResultToReturn = const SqlQueryResult(
        columns: [
          SqlColumn(name: 'ID', dataType: 'NUMBER'),
          SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
        ],
        rows: [
          [1, 'A'],
          [2, 'B'],
        ],
        returnedRows: 2,
        truncated: true,
        durationMs: 20,
      );

      final ctrl = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT * FROM EMPLEADOS;',
        service: fakeSvc,
      );
      addTearDown(ctrl.dispose);
      await ctrl.setMaxRows(2);

      await ctrl.runCurrentOrSelection();
      expect(ctrl.results, hasLength(1));
      expect(ctrl.lastResult?.truncated, isTrue);
      expect(ctrl.lastResult?.rows, hasLength(2));

      // 2. Para la siguiente página devolvemos 2 filas (lote lleno) aunque backend devuelva truncated=false
      fakeSvc.selectResultToReturn = const SqlQueryResult(
        columns: [
          SqlColumn(name: 'ID', dataType: 'NUMBER'),
          SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
        ],
        rows: [
          [3, 'C'],
          [4, 'D'],
        ],
        returnedRows: 2,
        truncated: false, // Backend manda false por límite en FETCH NEXT
        durationMs: 15,
      );

      // Primer loadMoreRows (llegó a 4 filas y detecta que aún hay más porque lote vino lleno)
      var success = await ctrl.loadMoreRows();
      expect(success, isTrue);
      expect(ctrl.lastResult?.rows, hasLength(4));
      expect(ctrl.lastResult?.truncated, isTrue);

      // 3. Tercera página devuelve 1 fila (lote incompleto, < limit 2)
      fakeSvc.selectResultToReturn = const SqlQueryResult(
        columns: [
          SqlColumn(name: 'ID', dataType: 'NUMBER'),
          SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
        ],
        rows: [
          [5, 'E'],
        ],
        returnedRows: 1,
        truncated: false,
        durationMs: 10,
      );

      // Segundo loadMoreRows (llega al final, ahora truncated es false)
      success = await ctrl.loadMoreRows();
      expect(success, isTrue);
      expect(ctrl.lastResult?.rows, hasLength(5));
      expect(ctrl.lastResult?.truncated, isFalse);
      expect(fakeSvc.lastSql, contains('OFFSET 4 ROWS FETCH NEXT'));
    });
  });
}
