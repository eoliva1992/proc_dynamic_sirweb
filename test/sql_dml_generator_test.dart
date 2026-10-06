import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/services/sql_dml_generator.dart';

SqlQueryResult _result() => const SqlQueryResult(
  columns: [
    SqlColumn(name: 'ID', dataType: 'NUMBER'),
    SqlColumn(name: 'NOMBRE', dataType: 'VARCHAR2'),
    SqlColumn(name: 'ACTIVO', dataType: 'NUMBER'),
  ],
  rows: [
    [1, "O'Brien", null],
    [2, 'Ana', 1],
  ],
  returnedRows: 2,
  truncated: false,
  durationMs: 5,
);

void main() {
  group('generateInsert', () {
    test('genera un INSERT por fila con literales correctos', () {
      final sql = generateInsert('CLIENTE', _result(), [0, 1]);
      final lines = sql.split('\n');
      expect(lines, hasLength(2));
      expect(
        lines[0],
        "INSERT INTO CLIENTE (ID, NOMBRE, ACTIVO) VALUES (1, 'O''Brien', NULL);",
      );
      expect(
        lines[1],
        "INSERT INTO CLIENTE (ID, NOMBRE, ACTIVO) VALUES (2, 'Ana', 1);",
      );
    });

    test('usa TO_DATE/TO_TIMESTAMP para columnas de fecha (evita ORA-01861)', () {
      const result = SqlQueryResult(
        columns: [
          SqlColumn(name: 'ID', dataType: 'NUMBER'),
          SqlColumn(name: 'F_ALTA', dataType: 'DATE'),
          SqlColumn(name: 'F_STAMP', dataType: 'TIMESTAMP(6)'),
        ],
        rows: [
          [1, '2026-10-06T00:00:00', '2026-10-06T12:30:45.123456Z'],
        ],
        returnedRows: 1,
        truncated: false,
        durationMs: 1,
      );
      final sql = generateInsert('CLIENTE', result, [0]);
      expect(
        sql,
        "INSERT INTO CLIENTE (ID, F_ALTA, F_STAMP) VALUES "
        "(1, TO_DATE('2026-10-06 00:00:00', 'YYYY-MM-DD HH24:MI:SS'), "
        "TO_TIMESTAMP('2026-10-06 12:30:45.123456', 'YYYY-MM-DD HH24:MI:SS.FF6'));",
      );
    });
  });

  group('generateUpdate', () {
    test('usa la columna clave en el WHERE y el resto en el SET', () {
      final sql = generateUpdate('CLIENTE', _result(), [1], ['ID']);
      expect(
        sql,
        "UPDATE CLIENTE SET NOMBRE = 'Ana', ACTIVO = 1 WHERE ID = 2;",
      );
    });

    test('sin columnas clave no genera nada', () {
      final sql = generateUpdate('CLIENTE', _result(), [1], []);
      expect(sql, isEmpty);
    });
  });

  group('generateMerge', () {
    test('arma USING/ON/UPDATE/INSERT con la clave dada', () {
      final sql = generateMerge('CLIENTE', _result(), [1], ['ID']);
      expect(sql, contains('MERGE INTO CLIENTE t'));
      expect(sql, contains('ON (t.ID = s.ID)'));
      expect(
        sql,
        contains(
          'WHEN MATCHED THEN UPDATE SET t.NOMBRE = s.NOMBRE, t.ACTIVO = s.ACTIVO',
        ),
      );
      expect(
        sql,
        contains('WHEN NOT MATCHED THEN INSERT (ID, NOMBRE, ACTIVO)'),
      );
    });

    test('si todas las columnas son clave omite WHEN MATCHED (SET vacío)', () {
      final sql = generateMerge(
        'CLIENTE',
        _result(),
        [1],
        ['ID', 'NOMBRE', 'ACTIVO'],
      );
      expect(sql, isNot(contains('WHEN MATCHED')));
      expect(sql, contains('ON (t.ID = s.ID AND t.NOMBRE = s.NOMBRE'));
      expect(
        sql,
        contains('WHEN NOT MATCHED THEN INSERT (ID, NOMBRE, ACTIVO)'),
      );
    });
  });
}
