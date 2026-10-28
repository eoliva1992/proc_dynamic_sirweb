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
  });
}
