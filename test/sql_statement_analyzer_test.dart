import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/services/sql_statement_analyzer.dart';

void main() {
  group('detectStatementKind', () {
    test('SELECT y WITH', () {
      expect(
        detectStatementKind('SELECT * FROM dual'),
        SqlStatementKind.select,
      );
      expect(
        detectStatementKind('WITH q AS (SELECT 1 FROM dual) SELECT * FROM q'),
        SqlStatementKind.select,
      );
    });

    test('DML', () {
      expect(
        detectStatementKind("INSERT INTO t VALUES (1)"),
        SqlStatementKind.dml,
      );
      expect(detectStatementKind("UPDATE t SET a = 1"), SqlStatementKind.dml);
      expect(detectStatementKind("DELETE FROM t"), SqlStatementKind.dml);
      expect(
        detectStatementKind("MERGE INTO t USING d ON (1=1)"),
        SqlStatementKind.dml,
      );
    });

    test('DDL', () {
      expect(
        detectStatementKind('CREATE TABLE t (a NUMBER)'),
        SqlStatementKind.ddl,
      );
      expect(
        detectStatementKind('ALTER TABLE t ADD (b NUMBER)'),
        SqlStatementKind.ddl,
      );
      expect(detectStatementKind('DROP TABLE t'), SqlStatementKind.ddl);
      expect(
        detectStatementKind('GRANT SELECT ON t TO u'),
        SqlStatementKind.ddl,
      );
      expect(
        detectStatementKind(
          'CREATE OR REPLACE PROCEDURE PRODUCTO.CALCULA_VALOR AS BEGIN NULL; END;',
        ),
        SqlStatementKind.ddl,
      );
      expect(
        detectStatementKind(
          'CREATE OR REPLACE EDITIONABLE PROCEDURE PRODUCTO.CALCULA_VALOR AS BEGIN NULL; END;',
        ),
        SqlStatementKind.ddl,
      );
    });

    test('PL/SQL anónimo y DECLARE; CREATE de objeto es DDL', () {
      expect(detectStatementKind('BEGIN NULL; END;'), SqlStatementKind.plsql);
      expect(
        detectStatementKind('DECLARE v NUMBER; BEGIN v := 1; END;'),
        SqlStatementKind.plsql,
      );
      expect(
        detectStatementKind(
          'CREATE OR REPLACE PROCEDURE p IS BEGIN NULL; END;',
        ),
        SqlStatementKind.ddl,
      );
      expect(
        detectStatementKind(
          'CREATE OR REPLACE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;',
        ),
        SqlStatementKind.ddl,
      );
    });

    test('EXPLAIN PLAN', () {
      expect(
        detectStatementKind('EXPLAIN PLAN FOR SELECT * FROM dual'),
        SqlStatementKind.explainPlan,
      );
    });

    test('ignora comentarios y strings al clasificar', () {
      expect(
        detectStatementKind(
          "-- SELECT esto es un comentario\nINSERT INTO t VALUES (1)",
        ),
        SqlStatementKind.dml,
      );
      expect(detectStatementKind(''), SqlStatementKind.unknown);
    });
  });

  group('splitStatements', () {
    test('separa por ; de nivel superior', () {
      const script = "SELECT 1 FROM dual; SELECT 2 FROM dual;";
      final stmts = splitStatements(script);
      expect(stmts, hasLength(2));
      expect(stmts[0].text, 'SELECT 1 FROM dual;');
      expect(stmts[1].text, 'SELECT 2 FROM dual;');
      expect(stmts[0].kind, SqlStatementKind.select);
    });

    test('no corta por ; interno de un bloque BEGIN...END', () {
      const script = '''
BEGIN
  INSERT INTO t VALUES (1);
  UPDATE t SET a = 2;
END;
SELECT * FROM dual;
''';
      final stmts = splitStatements(script);
      expect(stmts, hasLength(2));
      expect(stmts[0].kind, SqlStatementKind.plsql);
      expect(stmts[0].text, contains('INSERT INTO t'));
      expect(stmts[0].text, contains('UPDATE t'));
      expect(stmts[1].kind, SqlStatementKind.select);
    });

    test('respeta LOOP...END LOOP anidado dentro de BEGIN...END', () {
      const script = '''
BEGIN
  FOR i IN 1..3 LOOP
    INSERT INTO t VALUES (i);
  END LOOP;
END;
''';
      final stmts = splitStatements(script);
      expect(stmts, hasLength(1));
      expect(stmts[0].kind, SqlStatementKind.plsql);
    });

    test('ignora ; dentro de comentarios y strings', () {
      const script =
          "SELECT 'a;b' AS x FROM dual; -- comentario con ;\nSELECT 2 FROM dual;";
      final stmts = splitStatements(script);
      expect(stmts, hasLength(2));
    });

    test('terminador "/" en línea propia cierra un bloque PL/SQL', () {
      const script = '''
CREATE OR REPLACE PROCEDURE p IS
BEGIN
  NULL;
END;
/
SELECT * FROM dual;
''';
      final stmts = splitStatements(script);
      expect(stmts, hasLength(2));
      expect(stmts[0].kind, SqlStatementKind.ddl);
      expect(stmts[1].kind, SqlStatementKind.select);
    });

    test(
      'CREATE OR REPLACE PROCEDURE con variables antes de BEGIN no se fragmenta',
      () {
        const script = '''
CREATE OR REPLACE PROCEDURE pr_test (p_id IN NUMBER) IS
  v_num NUMBER := 10;
  v_texto VARCHAR2(50);
BEGIN
  v_texto := 'Hola mundo';
  NULL;
END pr_test;
SELECT 1 FROM dual;
''';
        final stmts = splitStatements(script);
        expect(stmts, hasLength(2));
        expect(stmts[0].kind, SqlStatementKind.ddl);
        expect(stmts[0].text, contains('v_num NUMBER := 10;'));
        expect(stmts[0].text, contains('v_texto := \'Hola mundo\';'));
        expect(stmts[1].kind, SqlStatementKind.select);
      },
    );

    test(
      'CREATE OR REPLACE FUNCTION con variables y múltiples BEGIN anidados',
      () {
        const script = '''
CREATE OR REPLACE FUNCTION fn_calculo(p_x IN NUMBER) RETURN NUMBER IS
  v_res NUMBER := 0;
BEGIN
  BEGIN
    v_res := p_x * 2;
  EXCEPTION
    WHEN OTHERS THEN
      v_res := -1;
  END;
  RETURN v_res;
END;
''';
        final stmts = splitStatements(script);
        expect(stmts, hasLength(1));
        expect(stmts[0].kind, SqlStatementKind.ddl);
      },
    );

    test('CREATE OR REPLACE PACKAGE y PACKAGE BODY se clasifican como DDL', () {
      const spec = '''
CREATE OR REPLACE PACKAGE pck_test AS
  PROCEDURE do_something;
  FUNCTION get_value RETURN VARCHAR2;
END pck_test;
''';
      final specStmts = splitStatements(spec);
      expect(specStmts, hasLength(1));
      expect(specStmts[0].kind, SqlStatementKind.ddl);

      const body = '''
CREATE OR REPLACE PACKAGE BODY pck_test AS
  PROCEDURE do_something IS
    v_dummy VARCHAR2(10);
  BEGIN
    NULL;
  END do_something;

  FUNCTION get_value RETURN VARCHAR2 IS
  BEGIN
    RETURN 'VAL';
  END get_value;
END pck_test;
''';
      final bodyStmts = splitStatements(body);
      expect(bodyStmts, hasLength(1));
      expect(bodyStmts[0].kind, SqlStatementKind.ddl);
    });
  });

  group('statementAtCursor', () {
    test('devuelve la sentencia que contiene el offset', () {
      const script = "SELECT 1 FROM dual; SELECT 2 FROM dual;";
      final stmt = statementAtCursor(script, 25);
      expect(stmt, isNotNull);
      expect(stmt!.text, 'SELECT 2 FROM dual;');
    });
  });

  group('extractDdlTarget', () {
    test('extrae nombre y tipo de procedimiento o función', () {
      final proc = extractDdlTarget(
        'CREATE OR REPLACE PROCEDURE schema1.pr_demo (p_id NUMBER) IS BEGIN NULL; END;',
      );
      expect(proc.objectType, 'PROCEDURE');
      expect(proc.objectName, 'pr_demo');

      final fn = extractDdlTarget(
        'CREATE OR REPLACE EDITIONABLE FUNCTION "FN_TOTAL" RETURN NUMBER IS BEGIN RETURN 1; END;',
      );
      expect(fn.objectType, 'FUNCTION');
      expect(fn.objectName, 'FN_TOTAL');
    });

    test('extrae nombre y tipo de package body', () {
      final pkg = extractDdlTarget(
        'CREATE OR REPLACE PACKAGE BODY PCK_TEST AS END PCK_TEST;',
      );
      expect(pkg.objectType, 'PACKAGE BODY');
      expect(pkg.objectName, 'PCK_TEST');
    });

    test('soporta múltiples modificadores y esquemas entrecomillados', () {
      final proc = extractDdlTarget(
        'CREATE OR REPLACE NONEDITIONABLE PROCEDURE "MY_SCHEMA" . "DO_ACTION" (p_val NUMBER) IS BEGIN NULL; END;',
      );
      expect(proc.objectType, 'PROCEDURE');
      expect(proc.objectName, 'DO_ACTION');
    });
  });

  group('Comandos cliente (DESC / DESCRIBE)', () {
    test('detectStatementKind clasifica DESC y DESCRIBE como command', () {
      expect(detectStatementKind('DESC emp;'), SqlStatementKind.command);
      expect(detectStatementKind('describe SCOTT.EMP'), SqlStatementKind.command);
      expect(detectStatementKind('DESC "SCHEMA"."TABLA";'), SqlStatementKind.command);
    });

    test('SqlCommandResult deserializa JSON y mapea a SqlQueryResult', () {
      final json = {
        'command': 'DESC',
        'output': 'SCOTT.EMP (TABLE): 2 columna(s).',
        'data': [
          {
            'columnName': 'EMPNO',
            'dataType': 'NUMBER',
            'dataLength': 22,
            'dataPrecision': 4,
            'dataScale': 0,
            'nullable': false,
          },
          {
            'columnName': 'ENAME',
            'dataType': 'VARCHAR2',
            'dataLength': 10,
            'dataPrecision': null,
            'dataScale': null,
            'nullable': true,
          },
        ],
      };

      final cmdResult = SqlCommandResult.fromJson(json, durationMs: 15);
      expect(cmdResult.command, 'DESC');
      expect(cmdResult.output, 'SCOTT.EMP (TABLE): 2 columna(s).');
      expect(cmdResult.columns, hasLength(2));
      expect(cmdResult.columns[0].columnName, 'EMPNO');
      expect(cmdResult.columns[0].nullable, false);

      final queryResult = cmdResult.toSqlQueryResult();
      expect(queryResult.columns, hasLength(6));
      expect(queryResult.rows, hasLength(2));
      expect(queryResult.rows[0][0], 'EMPNO');
      expect(queryResult.rows[0][1], 'NUMBER');
      expect(queryResult.rows[0][5], 'N');
      expect(queryResult.rows[1][5], 'Y');
    });
  });
}
