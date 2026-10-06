import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_state_controller.dart';

class _FakeSqlExecutorService implements SqlExecutorService {
  int selectCalls = 0;
  int dmlCalls = 0;
  int ddlCalls = 0;
  int commitCalls = 0;
  int rollbackCalls = 0;
  String? lastSql;
  String? lastSessionId;
  String? lastOwner;
  String? dmlSessionIdToReturn;

  @override
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    selectCalls++;
    lastSql = sql;
    lastOwner = owner;
    return const SqlQueryResult(
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
    bool Function()? cancelado,
  }) async {
    dmlCalls++;
    lastSql = sql;
    lastSessionId = sessionId;
    lastOwner = owner;
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
    String? objectName,
    String? objectType,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    ddlCalls++;
    lastSql = sql;
    lastOwner = owner;
    return const SqlDdlResult(
      ambiente: 'Desa',
      confirmed: true,
      autoCommitPossible: true,
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
    bool Function()? cancelado,
  }) async {
    lastSql = plsql;
    lastSessionId = sessionId;
    lastOwner = owner;
    return const SqlPlSqlResult(durationMs: 5);
  }

  @override
  Future<void> commitSession(
    String sessionId, {
    required String owner,
    bool Function()? cancelado,
  }) async {
    commitCalls++;
    lastSessionId = sessionId;
    lastOwner = owner;
  }

  @override
  Future<void> rollbackSession(
    String sessionId, {
    required String owner,
    bool Function()? cancelado,
  }) async {
    rollbackCalls++;
    lastSessionId = sessionId;
    lastOwner = owner;
  }

  @override
  Future<SqlExplainResult> explainPlan(
    String sql, {
    required String ambiente,
    String? owner,
    Map<String, dynamic>? binds,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
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

void main() {
  group('SqlExecutorStateController', () {
    setUp(() {
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

    test('ejecutar varios SELECT acumula un resultado por cada uno y '
        'selectResult permite alternar entre ellos', () async {
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
      expect(ctrl.selectedResultIndex, 1);
      expect(ctrl.lastResult, same(ctrl.results[1].result));

      ctrl.selectResult(0);
      expect(ctrl.selectedResultIndex, 0);
      expect(ctrl.lastResult, same(ctrl.results[0].result));

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
      'ejecutar un DML abre sesión y commit() la confirma y la cierra',
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
        expect(ctrl.hasPendingChanges, isFalse);
        expect(ctrl.log.last.message, contains('confirmados'));
      },
    );

    test('rollback() descarta la sesión abierta', () async {
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
    });

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
  });
}
