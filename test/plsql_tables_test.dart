import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/plsql_tables.dart';

void main() {
  group('extractSqlTables', () {
    test('FROM simple con y sin alias', () {
      const sql = 'SELECT * FROM poliza p, cliente WHERE p.cd = 1';
      final t = extractSqlTables(sql);
      expect(t['P'], 'POLIZA');
      expect(t['POLIZA'], 'POLIZA');
      expect(t['CLIENTE'], 'CLIENTE');
    });

    test('detecta TODAS las consultas del fuente, no sólo la primera', () {
      const sql = '''
PROCEDURE PR_X IS
BEGIN
  SELECT a FROM primera_tabla WHERE 1 = 1;
  SELECT b FROM segunda_tabla s WHERE 1 = 1;
  SELECT c FROM tercera_tabla t3, cuarta_tabla WHERE 1 = 1;
END;
''';
      final t = extractSqlTables(sql);
      expect(t.values.toSet(), {
        'PRIMERA_TABLA',
        'SEGUNDA_TABLA',
        'TERCERA_TABLA',
        'CUARTA_TABLA',
      });
      expect(t['S'], 'SEGUNDA_TABLA');
      expect(t['T3'], 'TERCERA_TABLA');
    });

    test('JOIN con y sin AS', () {
      const sql = '''
SELECT *
  FROM poliza p
  INNER JOIN cliente c ON c.id = p.id
  LEFT JOIN direccion AS d ON d.id = c.id
''';
      final t = extractSqlTables(sql);
      expect(t['C'], 'CLIENTE');
      expect(t['D'], 'DIRECCION');
      expect(t['P'], 'POLIZA');
    });

    test('UPDATE / INSERT INTO / MERGE INTO / DELETE FROM', () {
      const sql = '''
BEGIN
  UPDATE poliza p SET p.estado = 1;
  INSERT INTO log_evento (id) VALUES (1);
  MERGE INTO destino d USING origen o ON (d.id = o.id);
  DELETE FROM temporal t WHERE t.id = 1;
END;
''';
      final t = extractSqlTables(sql);
      expect(
        t.values.toSet(),
        containsAll(['POLIZA', 'LOG_EVENTO', 'DESTINO', 'TEMPORAL']),
      );
      expect(t['P'], 'POLIZA');
      expect(t['D'], 'DESTINO');
    });

    test('quita el esquema y las comillas', () {
      const sql = 'SELECT * FROM SIR.POLIZA p JOIN "SIR"."CLIENTE" c ON 1=1';
      final t = extractSqlTables(sql);
      expect(t['P'], 'POLIZA');
      expect(t['C'], 'CLIENTE');
    });

    test('no toma palabras reservadas como alias', () {
      const sql = 'SELECT * FROM poliza WHERE estado = 1';
      final t = extractSqlTables(sql);
      expect(t.values.toSet(), {'POLIZA'});
      expect(t.containsKey('WHERE'), isFalse);
    });

    test('ignora comentarios y literales', () {
      const sql = '''
BEGIN
  -- SELECT * FROM tabla_comentada;
  v := 'SELECT * FROM tabla_en_texto';
  SELECT x FROM tabla_real;
END;
''';
      final t = extractSqlTables(sql);
      expect(t.values.toSet(), {'TABLA_REAL'});
    });
  });

  group('extractAnchoredTables', () {
    test('detecta %TYPE y %ROWTYPE', () {
      const sql = '''
PROCEDURE PR_X IS
  v_cd  poliza.cd_poliza%TYPE;
  v_row cliente%ROWTYPE;
BEGIN
  NULL;
END;
''';
      expect(extractAnchoredTables(sql), {'POLIZA', 'CLIENTE'});
    });
  });

  group('tablesToPrefetch', () {
    test('combina tablas de consultas y de anclajes', () {
      const sql = '''
PROCEDURE PR_X IS
  v_cd poliza.cd_poliza%TYPE;
BEGIN
  SELECT x FROM recibo r WHERE r.id = v_cd;
END;
''';
      expect(tablesToPrefetch(sql), {'POLIZA', 'RECIBO'});
    });
  });
}
