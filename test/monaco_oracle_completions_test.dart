import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/_editor_plsql_completions.dart';
import 'package:proc_dynamic_sirweb/widgets/_monaco_oracle_completions.dart';
import 'package:proc_dynamic_sirweb/widgets/plsql_tables.dart';

void main() {
  group('Autocompletado Oracle para editores Monaco', () {
    test(
      'plsqlCompletionItems contiene palabras clave y funciones esenciales',
      () {
        final labels = plsqlCompletionItems.map((e) => e.label).toSet();

        // DML / SQL básico
        expect(labels, contains('SELECT'));
        expect(labels, contains('INSERT INTO'));
        expect(labels, contains('UPDATE'));
        expect(labels, contains('DELETE FROM'));
        expect(labels, contains('MERGE INTO'));

        // Bloques y estructuras PL/SQL
        expect(labels, contains('BEGIN...END'));
        expect(labels, contains('DECLARE...BEGIN'));
        expect(labels, contains('IF...THEN...END IF'));
        expect(labels, contains('FOR...LOOP (numérico)'));

        // Tipos Oracle
        expect(labels, contains('VARCHAR2'));
        expect(labels, contains('NUMBER'));
        expect(labels, contains('DATE'));

        // Funciones incorporadas Oracle
        expect(labels, contains('DBMS_OUTPUT.PUT_LINE'));
        expect(labels, contains('SQLERRM'));
      },
    );

    test(
      'Reconocimiento de notación de punto para miembros de tablas y paquetes',
      () {
        final re = RegExp(r'([A-Za-z]\w*)\.(\w*)$');

        final matchTable = re.firstMatch('SELECT p.');
        expect(matchTable, isNotNull);
        expect(matchTable!.group(1), 'p');
        expect(matchTable.group(2), '');

        final matchCol = re.firstMatch('WHERE cliente.nom');
        expect(matchCol, isNotNull);
        expect(matchCol!.group(1), 'cliente');
        expect(matchCol.group(2), 'nom');

        final matchPkg = re.firstMatch('DBMS_OUTPUT.');
        expect(matchPkg, isNotNull);
        expect(matchPkg!.group(1), 'DBMS_OUTPUT');
        expect(matchPkg.group(2), '');
      },
    );

    test('Reconocimiento de llamadas para autocompletar parámetros', () {
      final re = RegExp(r'([A-Za-z]\w*)(?:\.([A-Za-z]\w*))?\s*\(([^()]*)$');

      final matchSimple = re.firstMatch('PR_CALCULA_VALOR(');
      expect(matchSimple, isNotNull);
      expect(matchSimple!.group(1), 'PR_CALCULA_VALOR');
      expect(matchSimple.group(2), isNull);

      final matchPackage = re.firstMatch('PCK_PROCEDIMIENTO.COMPILAR(');
      expect(matchPackage, isNotNull);
      expect(matchPackage!.group(1), 'PCK_PROCEDIMIENTO');
      expect(matchPackage.group(2), 'COMPILAR');
    });

    test('Resolución de alias y tablas FROM para columnas contextuales', () {
      const sql = '''
        SELECT p.cd_producto, g.cd_garantia
        FROM productobiengarantia p
        JOIN garantia g ON p.cd_garantia = g.cd_garantia
      ''';
      final tableMap = extractSqlTables(sql);

      expect(tableMap['P'], 'PRODUCTOBIENGARANTIA');
      expect(tableMap['G'], 'GARANTIA');
      expect(tableMap['PRODUCTOBIENGARANTIA'], 'PRODUCTOBIENGARANTIA');
      expect(tableMap['GARANTIA'], 'GARANTIA');
    });

    test('Extracción de la palabra antes del cursor', () {
      expect(
        MonacoOracleCompletionsManager.wordBefore('SELECT cd_pro'),
        'cd_pro',
      );
      expect(MonacoOracleCompletionsManager.wordBefore('  FROM tab'), 'tab');
      expect(MonacoOracleCompletionsManager.wordBefore(''), '');
    });
  });
}
