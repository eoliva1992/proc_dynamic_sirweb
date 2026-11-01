import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/services/reverse_sql_yaml_context_extractor.dart';

void main() {
  const sampleYaml = '''
dbconfig:
  tables:
    - dml: merge
      name: PROCEDIMIENTODINAMICO
      columns: CD_PROCEDIMIENTO, IN_ACTIVO
      ignore_pk: CD_SUBRAMO
      order_by: CD_PROCEDIMIENTO ASC
      filters:
        CD_RAMO: "= 10"
        TX_DESCRIPCION: "IS NOT NULL"
      ins:
        CD_ESTADO:
          - 'A'
          - 'B'
      not_ins:
        CD_TIPO:
          - '99'
      betweens:
        FE_ALTA: "'2026-01-01' AND '2026-12-31'"
      set_columns:
        CD_USUARIO: "'ADMIN'"
    - dml: insert
      name: COTIZACION
      columns: ID_COTIZACION
''';

  group('ReverseSqlYamlContextExtractor', () {
    test('detecta número de líneas y contenido exacto', () {
      final lines = sampleYaml.split('\n');
      for (int i = 0; i < lines.length; i++) {
        // print('${i + 1}: ${lines[i]}');
      }
      expect(lines[4], contains('columns: CD_PROCEDIMIENTO'));
      expect(lines[5], contains('ignore_pk: CD_SUBRAMO'));
      expect(lines[6], contains('order_by: CD_PROCEDIMIENTO ASC'));
      expect(lines[8], contains('CD_RAMO: "= 10"'));
      expect(lines[11], contains('CD_ESTADO:'));
      expect(lines[23], contains('columns: ID_COTIZACION'));
    });

    test('detecta tabla y columnsList en línea de columns:', () {
      // Línea 5 (1-based): '      columns: CD_PROCEDIMIENTO, IN_ACTIVO'
      final ctx = ReverseSqlYamlContextExtractor.extractContext(
        fullText: sampleYaml,
        lineNumber: 5,
        column: 42,
      );

      expect(ctx.tableName, 'PROCEDIMIENTODINAMICO');
      expect(ctx.fieldType, YamlColumnFieldType.columnsList);
      expect(ctx.expectsColumn, isTrue);
    });

    test('detecta tabla y ignorePkList en línea de ignore_pk:', () {
      // Línea 6 (1-based): '      ignore_pk: CD_SUBRAMO'
      final ctx = ReverseSqlYamlContextExtractor.extractContext(
        fullText: sampleYaml,
        lineNumber: 6,
        column: 25,
      );

      expect(ctx.tableName, 'PROCEDIMIENTODINAMICO');
      expect(ctx.fieldType, YamlColumnFieldType.ignorePkList);
      expect(ctx.expectsColumn, isTrue);
    });

    test('detecta tabla y filterKey bajo bloque filters:', () {
      // Línea 9 (1-based): '        CD_RAMO: "= 10"'
      final ctx = ReverseSqlYamlContextExtractor.extractContext(
        fullText: sampleYaml,
        lineNumber: 9,
        column: 15,
      );

      expect(ctx.tableName, 'PROCEDIMIENTODINAMICO');
      expect(ctx.fieldType, YamlColumnFieldType.filterKey);
      expect(ctx.expectsColumn, isTrue);
    });

    test('detecta tabla y insKey bajo bloque ins:', () {
      // Línea 12 (1-based): '        CD_ESTADO:'
      final ctx = ReverseSqlYamlContextExtractor.extractContext(
        fullText: sampleYaml,
        lineNumber: 12,
        column: 17,
      );

      expect(ctx.tableName, 'PROCEDIMIENTODINAMICO');
      expect(ctx.fieldType, YamlColumnFieldType.insKey);
      expect(ctx.expectsColumn, isTrue);
    });

    test('detecta segunda tabla de forma independiente', () {
      // Línea 24 (1-based): '      columns: ID_COTIZACION' en COTIZACION
      final ctx = ReverseSqlYamlContextExtractor.extractContext(
        fullText: sampleYaml,
        lineNumber: 24,
        column: 25,
      );

      expect(ctx.tableName, 'COTIZACION');
      expect(ctx.fieldType, YamlColumnFieldType.columnsList);
      expect(ctx.expectsColumn, isTrue);
    });

    test('devuelve none si está fuera de bloques de columnas', () {
      // Línea 1: 'dbconfig:'
      final ctx = ReverseSqlYamlContextExtractor.extractContext(
        fullText: sampleYaml,
        lineNumber: 1,
        column: 5,
      );

      expect(ctx.fieldType, YamlColumnFieldType.none);
      expect(ctx.expectsColumn, isFalse);
    });
  });
}
