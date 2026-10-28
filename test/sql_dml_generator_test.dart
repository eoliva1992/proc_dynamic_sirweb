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

    test(
      'soporta fechas en formato DD/MM/YYYY y maneja vacíos/espacios como NULL',
      () {
        const result = SqlQueryResult(
          columns: [
            SqlColumn(name: 'FE_EFECTIVA', dataType: 'DATE'),
            SqlColumn(name: 'FE_TERMINO', dataType: 'DATE'),
            SqlColumn(name: 'FE_NULA', dataType: 'DATE'),
          ],
          rows: [
            ['01/01/2013 00:00:00', ' 00:00:00', null],
          ],
          returnedRows: 1,
          truncated: false,
          durationMs: 1,
        );
        final sql = generateInsert('EVENTOVALOR', result, [0]);
        expect(
          sql,
          "INSERT INTO EVENTOVALOR (FE_EFECTIVA, FE_TERMINO, FE_NULA) VALUES "
          "(TO_DATE('01/01/2013 00:00:00', 'DD/MM/YYYY HH24:MI:SS'), "
          "NULL, NULL);",
        );
      },
    );
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

    test(
      'fragmenta CLOB y textos mayores a 3000 caracteres con TO_CLOB para evitar ORA-01704',
      () {
        final largeText = 'A' * 7500;
        final result = SqlQueryResult(
          columns: const [
            SqlColumn(name: 'ID', dataType: 'NUMBER'),
            SqlColumn(name: 'DE_TEXTO', dataType: 'CLOB'),
          ],
          rows: [
            [1, largeText],
          ],
          returnedRows: 1,
          truncated: false,
          durationMs: 1,
        );
        final sql = generateInsert('PROCEDIMIENTODINAMICO', result, [0]);
        expect(
          sql,
          contains(
            "INSERT INTO PROCEDIMIENTODINAMICO (ID, DE_TEXTO) VALUES (1, ",
          ),
        );
        // Debe dividirse en 3 partes: 3000, 3000 y 1500 caracteres
        expect(
          sql,
          contains(
            "TO_CLOB('${'A' * 3000}') || TO_CLOB('${'A' * 3000}') || TO_CLOB('${'A' * 1500}')",
          ),
        );
      },
    );

    test('envuelve CLOB menor a 3000 caracteres en TO_CLOB', () {
      const shortText = 'BEGIN NULL; END;';
      final result = SqlQueryResult(
        columns: const [SqlColumn(name: 'DE_TEXTO', dataType: 'CLOB')],
        rows: const [
          [shortText],
        ],
        returnedRows: 1,
        truncated: false,
        durationMs: 1,
      );
      final sql = generateInsert('PROCEDIMIENTODINAMICO', result, [0]);
      expect(
        sql,
        "INSERT INTO PROCEDIMIENTODINAMICO (DE_TEXTO) VALUES (TO_CLOB('BEGIN NULL; END;'));",
      );
    });
  });
}
