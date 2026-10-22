import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/evento_info.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/services/sql_dml_generator.dart';

void main() {
  group('Generación de INSERT / MERGE desde valores de evento', () {
    final valores = [
      EventoValor(
        indice: 1,
        valor: 'VAL_A',
        descripcion: 'Valor A',
        raw: {
          'cdEvento': 'EVT01',
          'indice': 1,
          'valor': '100',
          'descripcion': "Texto con 'comilla'",
        },
      ),
      EventoValor(
        indice: 2,
        valor: 'VAL_B',
        descripcion: 'Valor B',
        raw: {
          'cdEvento': 'EVT01',
          'indice': 2,
          'valor': '200',
          'descripcion': 'Texto normal',
        },
      ),
    ];

    final cols = ['cdEvento', 'indice', 'valor', 'descripcion'];

    bool isNumericField(String col) {
      const numericFields = [
        'indice',
        'cdIndice',
        'index',
        'valor',
        'cdValor',
        'value',
      ];
      return numericFields.contains(col);
    }

    const knownDbColumnAliases = <String, String>{
      'MTINTINFERIORA': 'MT_INTERVALO_INFERIOR_A',
      'MTINTSUPERIORA': 'MT_INTERVALO_SUPERIOR_A',
      'MTINTINFERIORB': 'MT_INTERVALO_INFERIOR_B',
      'MTINTSUPERIORB': 'MT_INTERVALO_SUPERIOR_B',
      'CDINTINFERIOR': 'CD_INTERVALO_INFERIOR',
      'CDINTSUPERIOR': 'CD_INTERVALO_SUPERIOR',
      'VACOMPONENTE': 'VA_COMPONENTE',
      'VAMINIMOCOMPONENTE': 'VA_MINIMO_COMPONENTE',
      'VAMAXIMOCOMPONENTE': 'VA_MAXIMO_COMPONENTE',
      'VACOMPONENTEADICIONAL': 'VA_COMPONENTE_ADICIONAL',
      'PODEDUCIBLE': 'PO_DEDUCIBLE',
      'CDCATEGORIA': 'CD_CATEGORIA',
      'CDPERSONAPROVEEDOR': 'CD_PERSONA_PROVEEDOR',
      'CDCONCEPTO': 'CD_CONCEPTO',
      'CDSUBCONCEPTO': 'CD_SUB_CONCEPTO',
      'FEEFECTIVAEVENTO': 'FE_EFECTIVA_EVENTO',
      'FETERMINOEVENTO': 'FE_TERMINO_EVENTO',
      'FEINICIOREGISTRO': 'FE_INICIO_REGISTRO',
      'FETERMINOREGISTRO': 'FE_TERMINO_REGISTRO',
      'FEMODIFICACION': 'FE_MODIFICACION',
      'CDUSUARIO': 'CD_USUARIO',
      'DEINDICEEVENTO': 'DE_INDICE_EVENTO',
      'CDEVENTO': 'CD_EVENTO',
    };

    SqlQueryResult buildResult(
      List<String> columns,
      List<EventoValor> data, {
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
          for (final c in columns) () {
            final keyUpper = c.toUpperCase();
            final keyClean = c.replaceAll('_', '').toUpperCase();
            var matched = dbColMap[keyUpper] ?? dbColMap[keyClean];
            if (matched == null && knownDbColumnAliases.containsKey(keyClean)) {
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
              dataType: matched?.dataType ?? (isNumericField(c) ? 'NUMBER' : 'VARCHAR2'),
            );
          }(),
        ],
        rows: [
          for (final v in data)
            [
              for (final c in columns) v.raw[c],
            ],
        ],
        returnedRows: data.length,
        truncated: false,
        durationMs: 0,
      );
    }

    test('Convierte EventoValor a SqlQueryResult respetando tipos', () {
      final res = buildResult(cols, valores);
      expect(res.columns.length, 4);
      expect(res.columns[0].name, 'CD_EVENTO');
      expect(res.columns[0].dataType, 'VARCHAR2');
      expect(res.columns[1].name, 'INDICE');
      expect(res.columns[1].dataType, 'NUMBER');
      expect(res.rows.length, 2);
      expect(res.rows[0][0], 'EVT01');
      expect(res.rows[0][1], 1);
    });

    test('Genera INSERT para EVENTOVALOR con todas las filas', () {
      final res = buildResult(cols, valores);
      final sql = generateInsert('EVENTOVALOR', res, [0, 1]);
      final lines = sql.split('\n');
      expect(lines.length, 2);
      expect(
        lines[0],
        "INSERT INTO EVENTOVALOR (CD_EVENTO, INDICE, VALOR, DESCRIPCION) VALUES ('EVT01', 1, 100, 'Texto con ''comilla''');",
      );
      expect(
        lines[1],
        "INSERT INTO EVENTOVALOR (CD_EVENTO, INDICE, VALOR, DESCRIPCION) VALUES ('EVT01', 2, 200, 'Texto normal');",
      );
    });

    test('Genera INSERT para EVENTOVALOR solo con fila seleccionada', () {
      final res = buildResult(cols, valores);
      final sql = generateInsert('EVENTOVALOR', res, [1]);
      expect(
        sql,
        "INSERT INTO EVENTOVALOR (CD_EVENTO, INDICE, VALOR, DESCRIPCION) VALUES ('EVT01', 2, 200, 'Texto normal');",
      );
    });

    test('Usa el nombre original de las columnas desde la base de datos (ej: VA_DATO9)', () {
      final columnasDb = <({String name, String dataType})>[
        (name: 'CD_EVENTO', dataType: 'VARCHAR2'),
        (name: 'CD_INDICE', dataType: 'NUMBER'),
        (name: 'VA_DATO9', dataType: 'VARCHAR2'),
        (name: 'DE_VALOR', dataType: 'VARCHAR2'),
      ];

      final valoresConVaDato9 = [
        EventoValor(
          raw: {
            'cdEvento': 'EVT01',
            'cdIndice': 1,
            'vaDato9': 'ABC',
            'deValor': 'Test',
          },
        ),
      ];

      final res = buildResult(
        ['cdEvento', 'cdIndice', 'vaDato9', 'deValor'],
        valoresConVaDato9,
        dbColumns: columnasDb,
      );

      expect(res.columns[0].name, 'CD_EVENTO');
      expect(res.columns[1].name, 'CD_INDICE');
      expect(res.columns[2].name, 'VA_DATO9');
      expect(res.columns[3].name, 'DE_VALOR');

      final sql = generateInsert('EVENTOVALOR', res, [0]);
      expect(
        sql,
        "INSERT INTO EVENTOVALOR (CD_EVENTO, CD_INDICE, VA_DATO9, DE_VALOR) VALUES ('EVT01', 1, 'ABC', 'Test');",
      );
    });

    test('Mapea abreviaciones del backend a columnas reales exactas de EVENTOVALOR (ej: mtIntInferiorA -> MT_INTERVALO_INFERIOR_A)', () {
      final columnasDb = <({String name, String dataType})>[
        (name: 'CD_EVENTO', dataType: 'VARCHAR2'),
        (name: 'DE_INDICE_EVENTO', dataType: 'VARCHAR2'),
        (name: 'FE_EFECTIVA_EVENTO', dataType: 'DATE'),
        (name: 'VA_DATO1', dataType: 'VARCHAR2'),
        (name: 'VA_COMPONENTE', dataType: 'NUMBER'),
        (name: 'MT_INTERVALO_INFERIOR_A', dataType: 'NUMBER'),
        (name: 'MT_INTERVALO_SUPERIOR_A', dataType: 'NUMBER'),
        (name: 'CD_INTERVALO_INFERIOR', dataType: 'VARCHAR2'),
      ];

      final valores = [
        EventoValor(
          raw: {
            'cdEvento': '990108',
            'deIndiceEvento': '720|360200|1|0|0',
            'feEfectivaEvento': '12/08/2026',
            'vaDato1': '720',
            'vaComponente': 0.31,
            'mtIntInferiorA': 100,
            'mtIntSuperiorA': 500,
            'cdIntInferior': 'MIN',
          },
        ),
      ];

      final res = buildResult(
        [
          'cdEvento',
          'deIndiceEvento',
          'feEfectivaEvento',
          'vaDato1',
          'vaComponente',
          'mtIntInferiorA',
          'mtIntSuperiorA',
          'cdIntInferior',
        ],
        valores,
        dbColumns: columnasDb,
      );

      expect(res.columns[0].name, 'CD_EVENTO');
      expect(res.columns[1].name, 'DE_INDICE_EVENTO');
      expect(res.columns[2].name, 'FE_EFECTIVA_EVENTO');
      expect(res.columns[3].name, 'VA_DATO1');
      expect(res.columns[4].name, 'VA_COMPONENTE');
      expect(res.columns[5].name, 'MT_INTERVALO_INFERIOR_A');
      expect(res.columns[6].name, 'MT_INTERVALO_SUPERIOR_A');
      expect(res.columns[7].name, 'CD_INTERVALO_INFERIOR');

      final sql = generateInsert('EVENTOVALOR', res, [0]);
      expect(
        sql,
        contains('INSERT INTO EVENTOVALOR (CD_EVENTO, DE_INDICE_EVENTO, FE_EFECTIVA_EVENTO, VA_DATO1, VA_COMPONENTE, MT_INTERVALO_INFERIOR_A, MT_INTERVALO_SUPERIOR_A, CD_INTERVALO_INFERIOR)'),
      );
    });
  });
}
