import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/ejecucion_procedimiento.dart';

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

    test('acepta variablesDinamicasUsadas como lista de nombres (formato viejo)', () {
      final res = EjecucionResultado.fromJson({
        'variablesDinamicasUsadas': ['#FECHA#', '#USUARIO#'],
      });

      expect(res.variablesDinamicasUsadas.keys.toList(), [
        '#FECHA#',
        '#USUARIO#',
      ]);
      expect(res.variablesDinamicasUsadas['#FECHA#'], isNull);
    });

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

    test('expone el error de Oracle cuando viene', () {
      final res = EjecucionResultado.fromJson({
        'errorOracle': 'ORA-06550: line 1',
      });

      expect(res.tieneError, isTrue);
      expect(res.errorOracle, contains('ORA-06550'));
    });
  });

  group('EjecucionRequest.toJson', () {
    test('envía el contrato completo con los null explícitos', () {
      final json = const EjecucionRequest(
        cdEntidad: 1,
        nuCotizacion: 500,
      ).toJson();

      expect(json['cdEntidad'], 1);
      expect(json['nuCotizacion'], 500);
      expect(json.containsKey('nuPoliza'), isTrue);
      expect(json['nuPoliza'], isNull);
      expect(json.length, 18);
    });
  });

  group('EjecucionRequest.toBorradorJson', () {
    test('agrega deTexto e inConfiguracion al contrato de contexto', () {
      final json = const EjecucionRequest(
        cdEntidad: 1,
      ).toBorradorJson(deTexto: 'BEGIN NULL; END;', inConfiguracion: 'D');

      expect(json['deTexto'], 'BEGIN NULL; END;');
      expect(json['inConfiguracion'], 'D');
      expect(json['cdEntidad'], 1);
      expect(json.containsKey('nuPoliza'), isTrue);
      expect(json.length, 20);
    });

    test('manda inConfiguracion vacío cuando no se conoce', () {
      final json = const EjecucionRequest().toBorradorJson(deTexto: 'BEGIN');

      expect(json['inConfiguracion'], '');
    });
  });
}

