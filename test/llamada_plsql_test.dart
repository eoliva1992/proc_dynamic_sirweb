import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/llamada_plsql.dart';

void main() {
  group('ParametroFirma getters de tipo', () {
    test('esFecha reconoce DATE y variantes de TIMESTAMP', () {
      final pDate = ParametroFirma(
        nombre: 'P_FECHA',
        posicion: 1,
        modo: 'IN',
        tipo: 'DATE',
      );
      expect(pDate.esFecha, isTrue);
      expect(pDate.esFechaConHora, isFalse);

      final pTs = ParametroFirma(
        nombre: 'P_TS',
        posicion: 2,
        modo: 'IN',
        tipo: 'TIMESTAMP',
      );
      expect(pTs.esFecha, isTrue);
      expect(pTs.esFechaConHora, isTrue);

      final pTsTz = ParametroFirma(
        nombre: 'P_TS_TZ',
        posicion: 3,
        modo: 'IN',
        tipo: 'TIMESTAMP WITH TIME ZONE',
      );
      expect(pTsTz.esFecha, isTrue);
      expect(pTsTz.esFechaConHora, isTrue);

      final pVarchar = ParametroFirma(
        nombre: 'P_TEXTO',
        posicion: 4,
        modo: 'IN',
        tipo: 'VARCHAR2',
      );
      expect(pVarchar.esFecha, isFalse);
      expect(pVarchar.esFechaConHora, isFalse);
    });

    test('esNumerico y esEntero clasifican correctamente tipos Oracle', () {
      final pNumber = ParametroFirma(
        nombre: 'P_NUM',
        posicion: 1,
        modo: 'IN',
        tipo: 'NUMBER',
      );
      expect(pNumber.esNumerico, isTrue);
      expect(pNumber.esEntero, isFalse);

      final pInt = ParametroFirma(
        nombre: 'P_ID',
        posicion: 2,
        modo: 'IN',
        tipo: 'INTEGER',
      );
      expect(pInt.esNumerico, isTrue);
      expect(pInt.esEntero, isTrue);

      final pPls = ParametroFirma(
        nombre: 'P_INDEX',
        posicion: 3,
        modo: 'IN',
        tipo: 'PLS_INTEGER',
      );
      expect(pPls.esNumerico, isTrue);
      expect(pPls.esEntero, isTrue);

      final pFloat = ParametroFirma(
        nombre: 'P_FACTOR',
        posicion: 4,
        modo: 'IN',
        tipo: 'FLOAT',
      );
      expect(pFloat.esNumerico, isTrue);
      expect(pFloat.esEntero, isFalse);
    });

    test('LlamadaResultado deserializa firmas de diferentes ambientes con distinta cantidad de parametros', () {
      final jsonAmbienteA = {
        'ok': true,
        'objeto': 'PCK_TEST.CALCULAR',
        'firma': [
          {'nombre': 'P_A', 'posicion': 1, 'modo': 'IN', 'tipo': 'NUMBER'},
          {'nombre': 'P_B', 'posicion': 2, 'modo': 'IN', 'tipo': 'VARCHAR2'},
          {'nombre': 'P_C', 'posicion': 3, 'modo': 'IN', 'tipo': 'DATE'},
        ],
      };
      final resA = LlamadaResultado.fromJson(jsonAmbienteA);
      expect(resA.firma.length, 3);
      expect(resA.firma.map((p) => p.nombre).toList(), ['P_A', 'P_B', 'P_C']);

      // En ambiente B el mismo procedimiento tiene menos parámetros
      final jsonAmbienteB = {
        'ok': true,
        'objeto': 'PCK_TEST.CALCULAR',
        'firma': [
          {'nombre': 'P_A', 'posicion': 1, 'modo': 'IN', 'tipo': 'NUMBER'},
        ],
      };
      final resB = LlamadaResultado.fromJson(jsonAmbienteB);
      expect(resB.firma.length, 1);
      expect(resB.firma.first.nombre, 'P_A');
    });

    test('ParametroFirma de salida OUT no se bloquea aunque sea TABLE', () {
      final pOutTable = ParametroFirma(
        nombre: 'P_CUR_COTIZACIONES',
        posicion: 17,
        modo: 'OUT',
        tipo: 'TABLE',
        noSoportado: null,
      );
      expect(pOutTable.esEntrada, isFalse);
      expect(pOutTable.bloqueado, isFalse);
    });

    test('formato de tiempo muestra milisegundos y segundos', () {
      String formatearTiempo(int ms, {String prefix = ''}) {
        final double seg = ms / 1000.0;
        final String segStr;
        if (ms < 10) {
          segStr = seg.toStringAsFixed(3);
        } else {
          segStr = seg.toStringAsFixed(2);
        }
        return '$prefix$ms ms ($segStr s)';
      }

      expect(formatearTiempo(42), '42 ms (0.04 s)');
      expect(formatearTiempo(1450), '1450 ms (1.45 s)');
      expect(formatearTiempo(83), '83 ms (0.08 s)');
      expect(formatearTiempo(1, prefix: 'Oracle '), 'Oracle 1 ms (0.001 s)');
      expect(formatearTiempo(65430), '65430 ms (65.43 s)');
    });
  });
}

