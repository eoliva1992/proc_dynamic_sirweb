import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proc_dynamic_sirweb/models/sql_http_trace.dart';
import 'package:proc_dynamic_sirweb/services/server_config_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService().setBaseUrl('http://localhost:5000');
  });

  group('SqlHttpTraceEntry', () {
    test('formatea prettyRequestBody y prettyResponseBody con JSON válido', () {
      final trace = SqlHttpTraceEntry(
        id: 1,
        timestamp: DateTime(2026, 10, 19, 12, 0, 0),
        method: 'POST',
        url: 'http://localhost:5000/tools/sql/statement',
        endpoint: '/tools/sql/statement',
        requestBody: '{"owner":"SYSTEM","sql":"SELECT 1 FROM dual"}',
        responseBody: '{"success":true,"data":{"query":{"columns":["1"]}}}',
        statusCode: 200,
        status: SqlHttpTraceStatus.success,
      );

      expect(trace.prettyRequestBody, contains('  "owner": "SYSTEM"'));
      expect(trace.prettyResponseBody, contains('  "success": true'));
      expect(
        trace.toCurlCommand(),
        contains('curl -X POST "http://localhost:5000/tools/sql/statement"'),
      );
    });

    test('serializa y deserializa a JSON correctamente', () {
      final trace = SqlHttpTraceEntry(
        id: 10,
        timestamp: DateTime(2026, 10, 19, 10, 30, 0),
        method: 'POST',
        url: 'http://localhost:5000/tools/sql/explain',
        endpoint: '/tools/sql/explain',
        statusCode: 200,
        durationMs: 45,
        status: SqlHttpTraceStatus.success,
      );

      final json = trace.toJson();
      final restored = SqlHttpTraceEntry.fromJson(json);

      expect(restored.id, 10);
      expect(restored.method, 'POST');
      expect(restored.url, 'http://localhost:5000/tools/sql/explain');
      expect(restored.statusCode, 200);
      expect(restored.durationMs, 45);
      expect(restored.status, SqlHttpTraceStatus.success);
    });
  });

  group('SqlExecutorService HTTP Tracing', () {
    test('emite traza con request y response en executeSelect', () async {
      final traces = <SqlHttpTraceEntry>[];
      final service = SqlExecutorService();
      service.onHttpTrace = (t) => traces.add(t);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'OK',
            'data': {
              'kind': 'query',
              'query': {
                'columns': [
                  {'name': 'ID', 'dataType': 'NUMBER'},
                ],
                'rows': [
                  [100],
                ],
                'returnedRows': 1,
                'totalRows': 1,
                'durationMs': 12,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await service.executeSelect(
        'SELECT ID FROM DUAL',
        ambiente: 'Desa',
        owner: 'SYSTEM',
        client: mockClient,
      );

      expect(result.returnedRows, 1);
      expect(traces, isNotEmpty);
      final finalTrace = traces.last;
      expect(finalTrace.status, SqlHttpTraceStatus.success);
      expect(finalTrace.statusCode, 200);
      expect(finalTrace.endpoint, '/tools/sql/statement');
      expect(finalTrace.requestBody, contains('SELECT ID FROM DUAL'));
      expect(finalTrace.responseBody, contains('"totalRows":1'));
    });

    test(
      'registra status error en la traza cuando el backend responde error',
      () async {
        final traces = <SqlHttpTraceEntry>[];
        final service = SqlExecutorService();
        service.onHttpTrace = (t) => traces.add(t);

        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'ORA-00942: table or view does not exist',
            }),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        await expectLater(
          () => service.executeSelect(
            'SELECT * FROM NO_EXISTE',
            ambiente: 'Desa',
            owner: 'SYSTEM',
            client: mockClient,
          ),
          throwsException,
        );

        expect(traces, isNotEmpty);
        final finalTrace = traces.last;
        expect(finalTrace.status, SqlHttpTraceStatus.error);
        expect(finalTrace.statusCode, 400);
        expect(finalTrace.error, contains('ORA-00942'));
      },
    );
  });
}
