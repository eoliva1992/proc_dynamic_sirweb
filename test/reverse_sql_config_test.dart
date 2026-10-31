import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/reverse_sql_config.dart';

void main() {
  group('ReverseSqlConfig', () {
    const sampleYaml = '''
#Debe llevar las reglas de la configuración Yaml. Para mas información https://www.redhat.com/es/topics/automation/what-is-yaml 
dbconfig:
  tables:
    - dml: merge #merge | insert | update | delete, (required | string)
      name: procedimientodinamico #TableName, (required | string)
      pk_add: true #Completa la PrimaryKey, (opcional | bool)
      filters: #Representación del Where y And
        cd_procedimiento: "= 'SUGIERE_DIRECCION_MATRIZ_TRP'"

    - dml: update #merge | insert | update | delete, (required | string)
      name: productobiendato #TableName, (required | string)
      columns: cd_procedimiento_antes,in_matriz_certificado #Especificar columnas (Solo para update), (opcional | string)
      pk_add: true #Completa la PrimaryKey, (opcional | bool)
      filters: #Representación del Where y And
        cd_producto: "= 380100"
        cd_dato: "= 830059"
''';

    test('parseYaml extrae las tablas y filtros correctamente', () {
      final config = ReverseSqlConfig.parseYaml(sampleYaml);

      expect(config.tables.length, 2);

      final t1 = config.tables[0];
      expect(t1.dml, ReverseSqlDml.merge);
      expect(t1.name, 'procedimientodinamico');
      expect(t1.pkAdd, true);
      expect(
        t1.filters['cd_procedimiento'],
        "= 'SUGIERE_DIRECCION_MATRIZ_TRP'",
      );

      final t2 = config.tables[1];
      expect(t2.dml, ReverseSqlDml.update);
      expect(t2.name, 'productobiendato');
      expect(t2.columns, 'cd_procedimiento_antes,in_matriz_certificado');
      expect(t2.filters['cd_producto'], '= 380100');
      expect(t2.filters['cd_dato'], '= 830059');
    });

    test('toYaml y parseYaml mantienen roundtrip', () {
      final original = ReverseSqlConfig.parseYaml(sampleYaml);
      final generatedYaml = original.toYaml();
      final roundtrip = ReverseSqlConfig.parseYaml(generatedYaml);

      expect(roundtrip.tables.length, original.tables.length);
      expect(roundtrip.tables[0].name, original.tables[0].name);
      expect(roundtrip.tables[0].dml, original.tables[0].dml);
      expect(roundtrip.tables[1].columns, original.tables[1].columns);
    });

    test('plantilla vacía genera estructura inicial comentada', () {
      const emptyConfig = ReverseSqlConfig(tables: []);
      final yaml = emptyConfig.toYaml();

      expect(yaml.contains('dbconfig:'), isTrue);
      expect(yaml.contains('tables:'), isTrue);
      expect(yaml.contains('https://www.redhat.com'), isTrue);
    });

    test('toYaml omite claves de filtro vacías generadas durante edición', () {
      const config = ReverseSqlConfig(
        tables: [
          ReverseSqlTableConfig(
            dml: ReverseSqlDml.merge,
            name: 'procedimientodinamico',
            filters: {
              'cd_procedimiento': "= 'TEST'",
              '': "= 'VALOR_EN_EDICION'",
              '   ': "= 'OTRO'",
            },
          ),
        ],
      );
      final yaml = config.toYaml();
      expect(yaml.contains('cd_procedimiento: "= \'TEST\'"'), isTrue);
      expect(yaml.contains('VALOR_EN_EDICION'), isFalse);
    });

    test(
      'toYaml y parseYaml preservan el bloque ins como lista YAML estándar',
      () {
        const config = ReverseSqlConfig(
          tables: [
            ReverseSqlTableConfig(
              dml: ReverseSqlDml.insert,
              name: 'tabla_prueba',
              ins: {
                'cd_ramo': '1, 2, 3',
                'cd_subramo':
                    "'AUT_540100_ROBO_FIDELIDAD', 'AUT_540100_ROBO_FIDELIDAD'",
              },
            ),
          ],
        );

        final yaml = config.toYaml();
        expect(yaml.contains('ins:'), isTrue);
        // Debe emitir lista YAML estándar con guiones
        expect(yaml.contains('cd_ramo:'), isTrue);
        expect(yaml.contains('- 1'), isTrue);
        expect(yaml.contains('- 2'), isTrue);
        expect(yaml.contains('- 3'), isTrue);
        expect(yaml.contains('cd_subramo:'), isTrue);
        expect(yaml.contains("- 'AUT_540100_ROBO_FIDELIDAD'"), isTrue);

        final parsed = ReverseSqlConfig.parseYaml(yaml);
        expect(parsed.tables.length, 1);
        expect(parsed.tables.first.ins['cd_ramo'], '1, 2, 3');
        expect(
          parsed.tables.first.ins['cd_subramo'],
          "'AUT_540100_ROBO_FIDELIDAD', 'AUT_540100_ROBO_FIDELIDAD'",
        );
      },
    );

    test(
      'parseYaml convierte lista YAML de strings a formato SQL con comillas simples',
      () {
        const yamlConLista = '''
dbconfig:
  tables:
    - dml: merge
      name: procedimientodinamico
      ins:
        cd_procedimiento:
          - AUT_540100_ROBO_FIDELIDAD
          - AUT_540100_ROBO_FIDELIDAD_2
        cd_ramo:
          - 1
          - 2
''';
        final parsed = ReverseSqlConfig.parseYaml(yamlConLista);
        expect(parsed.tables.length, 1);
        final table = parsed.tables.first;
        // Los strings deben tener comillas simples de SQL ('val1', 'val2')
        expect(
          table.ins['cd_procedimiento'],
          "'AUT_540100_ROBO_FIDELIDAD', 'AUT_540100_ROBO_FIDELIDAD_2'",
        );
        // Los números deben quedar sin comillas (1, 2)
        expect(table.ins['cd_ramo'], '1, 2');
      },
    );

    test(
      'parsea dos tablas consecutivas con ins sin que la segunda contamine la primera',
      () {
        const yamlMultiTabla = '''
dbconfig:
  tables:
    - dml: merge #merge | insert | update | delete, (required | string)
      name: procedimientodinamico #TableName, (required | string)
      pk_add: true #Completa la PrimaryKey, (opcional | bool)
      ins: #Representación del IN (optional | string)
        cd_procedimiento:
          - AUT_540100_ROBO_FIDELIDAD
          - AUT_540100_ROBO_FIDELIDAD
    - dml: merge
      name: autorizacion
      pk_add: true
      filters: #Representación del Where y And
        cd_autorizacion_operacion: "= 540016"
''';
        final parsed = ReverseSqlConfig.parseYaml(yamlMultiTabla);

        // Deben existir exactamente 2 tablas
        expect(parsed.tables.length, 2);

        // Tabla 1: procedimientodinamico
        final t1 = parsed.tables[0];
        expect(t1.name, 'procedimientodinamico');
        expect(t1.dml, ReverseSqlDml.merge);
        expect(t1.pkAdd, true);
        expect(
          t1.ins['cd_procedimiento'],
          "'AUT_540100_ROBO_FIDELIDAD', 'AUT_540100_ROBO_FIDELIDAD'",
        );
        // t1 NO debe contener 'name', 'dml' ni 'pk_add' dentro de ins
        expect(t1.ins.containsKey('name'), isFalse);
        expect(t1.ins.containsKey('dml'), isFalse);
        expect(t1.ins.containsKey('pk_add'), isFalse);

        // Tabla 2: autorizacion
        final t2 = parsed.tables[1];
        expect(t2.name, 'autorizacion');
        expect(t2.dml, ReverseSqlDml.merge);
        expect(t2.pkAdd, true);
        expect(t2.filters['cd_autorizacion_operacion'], '= 540016');
        expect(t2.ins.isEmpty, isTrue);

        // Roundtrip toYaml -> parseYaml
        final regeneratedYaml = parsed.toYaml();
        final roundtrip = ReverseSqlConfig.parseYaml(regeneratedYaml);
        expect(roundtrip.tables.length, 2);
        expect(roundtrip.tables[0].name, 'procedimientodinamico');
        expect(roundtrip.tables[1].name, 'autorizacion');
      },
    );

    test(
      'preserva comillas simples explícitas escritas por el usuario en YAML',
      () {
        const yamlConComillas = '''
dbconfig:
  tables:
    - dml: merge
      name: mi_tabla
      ins:
        codigo:
          - '0123'
          - '0456'
''';
        final parsed = ReverseSqlConfig.parseYaml(yamlConComillas);
        expect(parsed.tables.first.ins['codigo'], "'0123', '0456'");

        final regenerated = parsed.toYaml();
        expect(regenerated.contains("- '0123'"), isTrue);
        expect(regenerated.contains("- '0456'"), isTrue);
      },
    );

    test(
      'parsea y serializa correctamente not_ins, betweens, exists, order_by y limit',
      () {
        const fullYaml = '''
dbconfig:
  tables:
    - dml: merge
      name: procedimientodinamico
      pk_add: true
      ins:
        cd_ramo:
          - 1
          - 2
      not_ins:
        cd_procedimiento:
          - 'AUT_DEPRECADO'
          - 'AUT_TEST'
      betweens:
        fe_alta: "'2026-01-01' AND '2026-12-31'"
      exists:
        - "SELECT 1 FROM autorizacion a WHERE a.cd_autorizacion = procedimientodinamico.cd_autorizacion"
      order_by: "fe_alta DESC, cd_procedimiento ASC"
      limit: 50
      filters:
        in_activo: "= 1"
''';
        final parsed = ReverseSqlConfig.parseYaml(fullYaml);
        expect(parsed.tables.length, 1);
        final t = parsed.tables.first;
        expect(t.name, 'procedimientodinamico');
        expect(t.dml, ReverseSqlDml.merge);
        expect(t.ins['cd_ramo'], '1, 2');
        expect(t.notIns['cd_procedimiento'], "'AUT_DEPRECADO', 'AUT_TEST'");
        expect(t.betweens['fe_alta'], "'2026-01-01' AND '2026-12-31'");
        expect(t.exists.length, 1);
        expect(t.exists.first, contains('SELECT 1 FROM autorizacion'));
        expect(t.orderBy, 'fe_alta DESC, cd_procedimiento ASC');
        expect(t.limit, 50);
        expect(t.filters['in_activo'], '= 1');

        // Roundtrip
        final regenerated = parsed.toYaml();
        final roundtrip = ReverseSqlConfig.parseYaml(regenerated);
        expect(roundtrip.tables.length, 1);
        final rt = roundtrip.tables.first;
        expect(rt.name, 'procedimientodinamico');
        expect(rt.notIns['cd_procedimiento'], "'AUT_DEPRECADO', 'AUT_TEST'");
        expect(rt.betweens['fe_alta'], "'2026-01-01' AND '2026-12-31'");
        expect(rt.exists.length, 1);
        expect(rt.orderBy, 'fe_alta DESC, cd_procedimiento ASC');
        expect(rt.limit, 50);
      },
    );

    group('Reordenamiento de tablas', () {
      const reorderYaml = '''
dbconfig:
  tables:
    - dml: insert
      name: tabla_padre
      filters:
        id: "= 1"
    - dml: merge
      name: tabla_hijo
      filters:
        id_padre: "= 1"
    - dml: update
      name: tabla_nieto
      filters:
        id_hijo: "= 1"
''';

      test('moveTableDown intercambia una tabla con su sucesor', () {
        final config = ReverseSqlConfig.parseYaml(reorderYaml);
        expect(config.tables.map((t) => t.name).toList(), [
          'tabla_padre',
          'tabla_hijo',
          'tabla_nieto',
        ]);

        final moved = config.moveTableDown(0);
        expect(moved.tables.map((t) => t.name).toList(), [
          'tabla_hijo',
          'tabla_padre',
          'tabla_nieto',
        ]);

        // toYaml debe reflejar la nueva secuencia en el texto generado
        final yaml = moved.toYaml();
        final idxHijo = yaml.indexOf('name: tabla_hijo');
        final idxPadre = yaml.indexOf('name: tabla_padre');
        expect(idxHijo < idxPadre, isTrue);
      });

      test('moveTableUp intercambia una tabla con su predecesor', () {
        final config = ReverseSqlConfig.parseYaml(reorderYaml);
        final moved = config.moveTableUp(2);
        expect(moved.tables.map((t) => t.name).toList(), [
          'tabla_padre',
          'tabla_nieto',
          'tabla_hijo',
        ]);
      });

      test('moveTableUp y moveTableDown en los extremos no alteran la lista', () {
        final config = ReverseSqlConfig.parseYaml(reorderYaml);
        expect(config.moveTableUp(0).tables, config.tables);
        expect(config.moveTableDown(2).tables, config.tables);
      });

      test('reorderTable reubica tablas según el protocolo ReorderableListView', () {
        final config = ReverseSqlConfig.parseYaml(reorderYaml);

        // Mover tabla_padre (0) al final (índice destino 3 según ReorderableListView)
        final movedEnd = config.reorderTable(0, 3);
        expect(movedEnd.tables.map((t) => t.name).toList(), [
          'tabla_hijo',
          'tabla_nieto',
          'tabla_padre',
        ]);

        // Mover tabla_nieto (1 en movedEnd) a la primera posición (0)
        final movedFront = movedEnd.reorderTable(1, 0);
        expect(movedFront.tables.map((t) => t.name).toList(), [
          'tabla_nieto',
          'tabla_hijo',
          'tabla_padre',
        ]);
      });
    });
  });
}
