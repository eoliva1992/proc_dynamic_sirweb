import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/ejecucion_procedimiento.dart';
import 'package:proc_dynamic_sirweb/models/sql_http_trace.dart';

void main() {
  group('EjecucionResultado.fromJson', () {
    test('parsea camposDesdeBd como mapa campo → valor', () {
      final res = EjecucionResultado.fromJson({
        'ambiente': 'Desa',
        'cdProcedimiento': 'DR_TEST',
        'borrador': true,
        'contexto': {
          'tipo': 'COTIZACION',
          'record': 'r_cotizacion',
          'camposDesdeBd': {'CD_PRODUCTO': '10', 'NU_ITEM': 1},
          'camposSobreescritos': ['CD_AREA'],
          'camposSinResolver': ['NU_ENDOSO'],
        },
        'salidas': {'VA_RESULTADO': 'OK'},
        'variablesDinamicasUsadas': {'#FECHA#': '06/09/2026'},
        'traza': ['linea 1', 'linea 2'],
        'duracionMs': 42,
        'rollback': true,
        'commitDetectado': false,
      });

      expect(res.borrador, isTrue);
      expect(res.contexto.camposDesdeBd, {'CD_PRODUCTO': '10', 'NU_ITEM': 1});
      expect(res.contexto.camposSobreescritos, ['CD_AREA']);
      expect(res.contexto.camposSinResolver, ['NU_ENDOSO']);
      expect(res.salidas['VA_RESULTADO'], 'OK');
      expect(res.variablesDinamicasUsadas['#FECHA#'], '06/09/2026');
      expect(res.traza.length, 2);
      expect(res.duracionMs, 42);
      expect(res.rollback, isTrue);
      expect(res.commitDetectado, isFalse);
      expect(res.tieneError, isFalse);
    });

    test('borrador es false cuando no viene en la respuesta', () {
      final res = EjecucionResultado.fromJson({'cdProcedimiento': 'DR_TEST'});

      expect(res.borrador, isFalse);
    });

    test(
      'acepta variablesDinamicasUsadas como lista de nombres (formato viejo)',
      () {
        final res = EjecucionResultado.fromJson({
          'variablesDinamicasUsadas': ['#FECHA#', '#USUARIO#'],
        });

        expect(res.variablesDinamicasUsadas.keys.toList(), [
          '#FECHA#',
          '#USUARIO#',
        ]);
        expect(res.variablesDinamicasUsadas['#FECHA#'], isNull);
      },
    );

    test('acepta el formato viejo de camposDesdeBd (lista de nombres)', () {
      final res = EjecucionResultado.fromJson({
        'contexto': {
          'camposDesdeBd': ['CD_PRODUCTO', 'NU_ITEM'],
        },
      });

      expect(res.contexto.camposDesdeBd.keys.toList(), [
        'CD_PRODUCTO',
        'NU_ITEM',
      ]);
      expect(res.contexto.camposDesdeBd['CD_PRODUCTO'], isNull);
    });

    test('tolera mapas no tipados y campos ausentes', () {
      final res = EjecucionResultado.fromJson({
        'contexto': <dynamic, dynamic>{
          'camposDesdeBd': <dynamic, dynamic>{'CD_AREA': 3},
        },
        'salidas': <dynamic, dynamic>{'X': 1},
      });

      expect(res.contexto.camposDesdeBd['CD_AREA'], 3);
      expect(res.salidas['X'], 1);
      expect(res.traza, isEmpty);
      expect(res.variablesDinamicasUsadas, isEmpty);
    });

    test('parsea variablesDeclaradas con nombre, tipo y valor inicial', () {
      final res = EjecucionResultado.fromJson({
        'variablesDeclaradas': [
          {
            'nombre': 'v_total',
            'tipo': 'NUMBER',
            'valorInicial': null,
            'valor': 125,
          },
          {
            'nombre': 'v_desc',
            'tipo': 'VARCHAR2(30)',
            'valorInicial': 'OK',
            'valor': 'OK',
          },
        ],
      });
      expect(res.variablesDeclaradas.length, 2);
      expect(res.variablesDeclaradas.first.nombre, 'v_total');
      expect(res.variablesDeclaradas.first.tipo, 'NUMBER');
      expect(res.variablesDeclaradas.first.valorInicial, isNull);
      expect(res.variablesDeclaradas.first.valor, 125);
      expect(res.variablesDeclaradas.first.cambio, isTrue);
      expect(res.variablesDeclaradas.last.valor, 'OK');
      expect(res.variablesDeclaradas.last.cambio, isFalse);
      expect(res.variablesDeclaradas.first.declaracion, 'v_total NUMBER;');
      expect(
        res.variablesDeclaradas.last.declaracion,
        'v_desc VARCHAR2(30) := OK;',
      );
    });
    test('variablesDeclaradas queda vacia si el backend no la manda', () {
      final res = EjecucionResultado.fromJson({'cdProcedimiento': 'DR_TEST'});
      expect(res.variablesDeclaradas, isEmpty);
    });
    test('acepta variablesDeclaradas como lista de nombres o mapa', () {
      final lista = EjecucionResultado.fromJson({
        'variablesDeclaradas': ['v_a', 'v_b'],
      });
      expect(lista.variablesDeclaradas.map((v) => v.nombre).toList(), [
        'v_a',
        'v_b',
      ]);
      expect(lista.variablesDeclaradas.first.declaracion, 'v_a;');
      final mapa = EjecucionResultado.fromJson({
        'variablesDeclaradas': {'v_c': 'DATE'},
      });
      expect(mapa.variablesDeclaradas.single.nombre, 'v_c');
      expect(mapa.variablesDeclaradas.single.tipo, 'DATE');
    });
    test('expone el error de Oracle cuando viene', () {
      final res = EjecucionResultado.fromJson({
        'errorOracle': 'ORA-06550: line 1',
      });

      expect(res.tieneError, isTrue);
      expect(res.errorOracle, contains('ORA-06550'));
    });

    test('acepta y conserva httpTrace opcional', () {
      final trace = SqlHttpTraceEntry(
        id: 1,
        timestamp: DateTime.now(),
        method: 'POST',
        url: 'http://localhost/tools/procedimiento-dinamico/P_TEST/ejecutar',
        endpoint: '/tools/procedimiento-dinamico/P_TEST/ejecutar',
        requestHeaders: {'content-type': 'application/json'},
        requestBody: '{"cdEntidad":30}',
        statusCode: 200,
        durationMs: 45,
        responseBody: '{"salidas":{"RES":1}}',
      );

      final res = EjecucionResultado.fromJson({
        'cdProcedimiento': 'P_TEST',
        'salidas': {'RES': 1},
      }, httpTrace: trace);

      expect(res.httpTrace, isNotNull);
      expect(res.httpTrace!.statusCode, 200);
      expect(res.httpTrace!.durationMs, 45);
      expect(res.httpTrace!.method, 'POST');
    });
  });

  group('EjecucionRequest.toJson', () {
    test('usa 30 como valor por defecto de cdEntidad', () {
      final json = const EjecucionRequest().toJson();
      expect(json['cdEntidad'], 30);
    });

    test('envía el contrato completo con los null explícitos', () {
      final json = const EjecucionRequest(
        cdEntidad: 30,
        nuCotizacion: 500,
      ).toJson();

      expect(json['cdEntidad'], 30);
      expect(json['nuCotizacion'], 500);
      expect(json.containsKey('nuPoliza'), isTrue);
      expect(json['nuPoliza'], isNull);
      expect(json.containsKey('nuBienAsegurado'), isTrue);
      expect(json['nuBienAsegurado'], isNull);
      expect(json.containsKey('capturarVariables'), isTrue);
      expect(json['capturarVariables'], isNull);
      expect(json.length, 20);
    });
  });

  group('EjecucionRequest.toBorradorJson', () {
    test('agrega deTexto e inConfiguracion al contrato de contexto', () {
      final json = const EjecucionRequest(
        cdEntidad: 30,
      ).toBorradorJson(deTexto: 'BEGIN NULL; END;', inConfiguracion: 'D');

      expect(json['deTexto'], 'BEGIN NULL; END;');
      expect(json['inConfiguracion'], 'D');
      expect(json['cdEntidad'], 30);
      expect(json.containsKey('nuPoliza'), isTrue);
      expect(json.containsKey('nuBienAsegurado'), isTrue);
      expect(json.containsKey('capturarVariables'), isTrue);
      expect(json.length, 22);
    });

    test('manda inConfiguracion vacío cuando no se conoce', () {
      final json = const EjecucionRequest().toBorradorJson(deTexto: 'BEGIN');

      expect(json['inConfiguracion'], '');
    });
  });
}
