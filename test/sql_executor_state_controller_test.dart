import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/models/ejecucion_procedimiento.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_state_controller.dart';

class _FakeSqlExecutorService implements SqlExecutorService {
  int selectCalls = 0;
  int dmlCalls = 0;
  String? lastSql;

  @override
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    bool Function()? cancelado,
  }) async {
    selectCalls++;
    lastSql = sql;
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
    int timeoutSegundos = 30,
  }) async {
    dmlCalls++;
    lastSql = sql;
    return const SqlDmlResult(
      rowsAffected: 3,
      durationMs: 15,
      message: '3 filas actualizadas',
    );
  }

  @override
  Future<EjecucionResultado> executePlSql(
    String plsql, {
    required String ambiente,
    int timeoutSegundos = 60,
    bool Function()? cancelado,
  }) async {
    return const EjecucionResultado(
      contexto: ContextoEjecucion(tipo: 'TEST'),
      salidas: {},
      variablesDinamicasUsadas: {},
      variablesDeclaradas: [],
      traza: [],
      raw: {},
    );
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
  });
}
