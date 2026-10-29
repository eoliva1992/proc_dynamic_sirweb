import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proc_dynamic_sirweb/services/server_config_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService().setBaseUrl('http://localhost:5000');
  });

  group('SqlExecutorService - executeDdl', () {
    test('envía confirmar=true en el cuerpo del request', () async {
      late Map<String, dynamic> capturedBody;

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/tools/sql/statement');
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'OK',
            'data': {
              'kind': 'ddl',
              'ddl': {
                'ambiente': 'Desa',
                'confirmed': true,
                'autoCommitPossible': true,
                'durationMs': 12,
                'errors': [],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await SqlExecutorService().executeDdl(
        'CREATE TABLE test_tab (id NUMBER)',
        ambiente: 'Desa',
        owner: 'SYSTEM',
        client: mockClient,
      );

      expect(capturedBody['confirmar'], isTrue);
      expect(capturedBody['owner'], 'SYSTEM');
      expect(capturedBody['ambiente'], 'Desa');
      expect(capturedBody['sql'], 'CREATE TABLE test_tab (id NUMBER)');
      expect(result.confirmed, isTrue);
      expect(result.autoCommitPossible, isTrue);
      expect(result.errors, isEmpty);
    });

    test(
      'parsea errores de compilación con claves en mayúsculas o minúsculas',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'kind': 'ddl',
                'ddl': {
                  'ambiente': 'Desa',
                  'confirmed': true,
                  'autoCommitPossible': true,
                  'durationMs': 15,
                  'compileErrors': [
                    {
                      'LINE': 4,
                      'POSITION': 12,
                      'TEXT': 'PLS-00201: identifier must be declared',
                      'ATTRIBUTE': 'ERROR',
                    },
                  ],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final result = await SqlExecutorService().executeDdl(
          'CREATE PROCEDURE fail_proc AS BEGIN x := 1; END;',
          ambiente: 'Desa',
          owner: 'SYSTEM',
          client: mockClient,
        );

        expect(result.errors, hasLength(1));
        expect(result.errors.first.line, 4);
        expect(result.errors.first.position, 12);
        expect(result.errors.first.text, contains('PLS-00201'));
      },
    );

    test('executeSelect y executeDml envían confirmar=false', () async {
      Map<String, dynamic>? selectBody;
      Map<String, dynamic>? dmlBody;

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['sql'] == 'SELECT 1 FROM DUAL') {
          selectBody = body;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'kind': 'query',
                'query': {
                  'columns': ['1'],
                  'rows': [
                    [1],
                  ],
                  'totalRows': 1,
                  'durationMs': 5,
                },
              },
            }),
            200,
          );
        } else {
          dmlBody = body;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'kind': 'dml',
                'dml': {'rowsAffected': 1, 'durationMs': 8},
              },
            }),
            200,
          );
        }
      });

      await SqlExecutorService().executeSelect(
        'SELECT 1 FROM DUAL;',
        ambiente: 'Desa',
        owner: 'SYSTEM',
        client: mockClient,
      );

      await SqlExecutorService().executeDml(
        'UPDATE test SET a = 1;',
        ambiente: 'Desa',
        owner: 'SYSTEM',
        client: mockClient,
      );

      expect(selectBody?['sql'], 'SELECT 1 FROM DUAL');
      expect(dmlBody?['sql'], 'UPDATE test SET a = 1');
      expect(selectBody?['confirmar'], isFalse);
      expect(dmlBody?['confirmar'], isFalse);
    });

    test('buildPagedSelectSql envuelve la consulta con OFFSET y FETCH NEXT', () {
      final sql1 = 'SELECT * FROM USUARIO;';
      final paged1 = buildPagedSelectSql(sql1, offset: 50, limit: 100);
      expect(
        paged1,
        'SELECT * FROM (\nSELECT * FROM USUARIO\n) OFFSET 50 ROWS FETCH NEXT 100 ROWS ONLY',
      );

      final sql2 = 'SELECT id, nombre FROM CLIENTES WHERE st = 1';
      final paged2 = buildPagedSelectSql(sql2, offset: 0, limit: 500);
      expect(
        paged2,
        'SELECT * FROM (\nSELECT id, nombre FROM CLIENTES WHERE st = 1\n) OFFSET 0 ROWS FETCH NEXT 500 ROWS ONLY',
      );
    });
  });
}
