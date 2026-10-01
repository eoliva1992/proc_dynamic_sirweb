import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/schema_source_search.dart';

void main() {
  group('SchemaSourceSearch models', () {
    test('deserializa respuesta JSON correctamente', () {
      const jsonStr = '''
      {
        "success": true,
        "message": null,
        "error": null,
        "data": {
          "objects": [
            {
              "owner": "SIR",
              "name": "PCK_FACTURACION",
              "objectType": "PACKAGE",
              "matchCount": 5,
              "firstLine": 42
            }
          ],
          "matches": [
            {
              "owner": "SIR",
              "name": "PCK_FACTURACION",
              "objectType": "PACKAGE",
              "line": 42,
              "text": "v_importe := p_monto * 1.18;"
            },
            {
              "owner": "SIR",
              "name": "PCK_FACTURACION",
              "objectType": "PACKAGE",
              "line": 105,
              "text": "IF v_importe > 1000 THEN"
            }
          ]
        }
      }
      ''';

      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      final data = decoded['data'] as Map<String, dynamic>;
      final result = SchemaSourceSearchResult.fromJson(data);

      expect(result.isEmpty, isFalse);
      expect(result.objects.length, equals(1));
      expect(result.matches.length, equals(2));

      final obj = result.objects.first;
      expect(obj.owner, equals('SIR'));
      expect(obj.name, equals('PCK_FACTURACION'));
      expect(obj.objectType, equals('PACKAGE'));
      expect(obj.matchCount, equals(5));
      expect(obj.firstLine, equals(42));

      final match1 = result.matches[0];
      expect(match1.line, equals(42));
      expect(match1.text, contains('v_importe'));

      final match2 = result.matches[1];
      expect(match2.line, equals(105));
    });

    test(
      'maneja JSON con listas vacías y campos alternativos en mayúsculas',
      () {
        final raw = {
          'OBJECTS': [
            {
              'OWNER': 'SIR',
              'NAME': 'PR_CALCULAR',
              'OBJECT_TYPE': 'procedure',
              'MATCH_COUNT': 1,
              'FIRST_LINE': 12,
            },
          ],
          'MATCHES': [
            {
              'OWNER': 'SIR',
              'NAME': 'PR_CALCULAR',
              'OBJECT_TYPE': 'procedure',
              'LINE': 12,
              'TEXT': 'BEGIN NULL; END;',
            },
          ],
        };

        final result = SchemaSourceSearchResult.fromJson(raw);
        expect(result.objects.length, equals(1));
        expect(result.objects.first.name, equals('PR_CALCULAR'));
        expect(result.objects.first.objectType, equals('PROCEDURE'));
        expect(result.matches.first.line, equals(12));
      },
    );
  });
}
