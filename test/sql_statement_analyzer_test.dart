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
    });

    test('PL/SQL: bloque anónimo, CREATE OR REPLACE y DECLARE', () {
      expect(detectStatementKind('BEGIN NULL; END;'), SqlStatementKind.plsql);
      expect(
        detectStatementKind('DECLARE v NUMBER; BEGIN v := 1; END;'),
        SqlStatementKind.plsql,
      );
      expect(
        detectStatementKind(
          'CREATE OR REPLACE PROCEDURE p IS BEGIN NULL; END;',
        ),
        SqlStatementKind.plsql,
      );
      expect(
        detectStatementKind(
          'CREATE OR REPLACE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;',
        ),
        SqlStatementKind.plsql,
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
      expect(stmts[0].kind, SqlStatementKind.plsql);
      expect(stmts[1].kind, SqlStatementKind.select);
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
}
