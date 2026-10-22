import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/dato_info.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/services/sql_dml_generator.dart';

void main() {
  group('Generación de INSERT / MERGE desde valores de tabla de dato', () {
    final valores = [
      ValorTabla(
        raw: {
          'cdTabla': 202,
          'deIndiceDato': 'IND_A',
          'deDato': 'Descripción A',
          'vaDato1': '1500',
          'vaDato2': '2500',
          'feEfectivaInformacion': '2026-01-01',
          'cdUsuario': 'USER_1',
        },
      ),
      ValorTabla(
        raw: {
          'cdTabla': 202,
          'deIndiceDato': 'IND_B',
          'deDato': "Texto con 'comilla'",
          'vaDato1': '3000',
          'vaDato2': '4000',
          'feEfectivaInformacion': '2026-02-01',
          'cdUsuario': 'USER_2',
        },
      ),
    ];

    final cols = [
      'cdTabla',
      'deIndiceDato',
      'deDato',
      'vaDato1',
      'vaDato2',
      'feEfectivaInformacion',
      'cdUsuario',
    ];

    const knownDbColumnAliases = <String, String>{
      'DEINDICEDATO': 'DE_INDICE_DATO',
      'DEDATO': 'DE_DATO',
      'VADATO1': 'VA_DATO1',
      'VADATO2': 'VA_DATO2',
      'VADATO3': 'VA_DATO3',
      'VADATO4': 'VA_DATO4',
      'VADATO5': 'VA_DATO5',
      'VADATO6': 'VA_DATO6',
      'FEEFECTIVAINFORMACION': 'FE_EFECTIVA_INFORMACION',
      'FETERMINOINFORMACION': 'FE_TERMINO_INFORMACION',
      'INSUSPENDIDO': 'IN_SUSPENDIDO',
      'INVALORDEFECTO': 'IN_VALOR_DEFECTO',
      'INNOVALIDO': 'IN_NO_VALIDO',
      'FEMODIFICACION': 'FE_MODIFICACION',
      'CDUSUARIO': 'CD_USUARIO',
      'CDTABLA': 'CD_TABLA',
    };

    bool isNumericField(String col) {
      final upper = col.toUpperCase();
      final clean = upper.replaceAll('_', '');
      return upper.startsWith('VA_DATO') ||
          upper == 'CD_TABLA' ||
          upper == 'CD_DATO' ||
          clean.startsWith('VADATO') ||
          clean == 'CDTABLA' ||
          clean == 'CDDATO';
    }

    SqlQueryResult buildResult(
      List<String> columns,
      List<ValorTabla> data, {
      List<({String name, String dataType})>? dbColumns,
    }) {
      final dbColMap = <String, ({String name, String dataType})>{};
      if (dbColumns != null) {
        for (final col in dbColumns) {
          final clean = col.name.replaceAll('_', '').toUpperCase();
          dbColMap[clean] = col;
          dbColMap[col.name.toUpperCase()] = col;
        }
      }

      return SqlQueryResult(
        columns: [
          for (final c in columns)
            () {
              final keyUpper = c.toUpperCase();
              final keyClean = c.replaceAll('_', '').toUpperCase();
              var matched = dbColMap[keyUpper] ?? dbColMap[keyClean];
              if (matched == null &&
                  knownDbColumnAliases.containsKey(keyClean)) {
                final dbName = knownDbColumnAliases[keyClean]!;
                matched = dbColMap[dbName];
                if (matched == null) {
                  return SqlColumn(
                    name: dbName,
                    dataType: isNumericField(c) ? 'NUMBER' : 'VARCHAR2',
                  );
                }
              }
              return SqlColumn(
                name: matched?.name ?? c.toUpperCase(),
                dataType:
                    matched?.dataType ??
                    (isNumericField(c) ? 'NUMBER' : 'VARCHAR2'),
              );
            }(),
        ],
        rows: [
          for (final v in data) [for (final c in columns) v.raw[c]],
        ],
        returnedRows: data.length,
        truncated: false,
        durationMs: 0,
      );
    }

    test('Genera script INSERT válido para TABLAINFORMACION', () {
      final result = buildResult(cols, valores);
      final script = generateInsert('TABLAINFORMACION', result, [0, 1]);

      expect(script, contains('INSERT INTO TABLAINFORMACION'));
      expect(script, contains('CD_TABLA'));
      expect(script, contains('DE_INDICE_DATO'));
      expect(script, contains('VA_DATO1'));
      expect(script, contains("Texto con ''comilla''"));
    });

    test('Genera script MERGE con columnas clave', () {
      final result = buildResult(cols, valores);
      final script = generateMerge(
        'TABLAINFORMACION',
        result,
        [0],
        ['CD_TABLA', 'DE_INDICE_DATO'],
      );

      expect(script, contains('MERGE INTO TABLAINFORMACION t'));
      expect(script, contains('t.CD_TABLA = s.CD_TABLA'));
      expect(script, contains('t.DE_INDICE_DATO = s.DE_INDICE_DATO'));
      expect(script, contains('WHEN MATCHED THEN UPDATE SET'));
      expect(script, contains('WHEN NOT MATCHED THEN INSERT'));
    });
  });
}
