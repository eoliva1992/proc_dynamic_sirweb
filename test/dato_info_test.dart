import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/dato_info.dart';

void main() {
  group('DatoInfo parsing with new server format', () {
    test(
      'Parsea respuesta con formato anidado {dato: ..., productos: [...]}',
      () {
        const rawJson = '''
      {
        "success": true,
        "message": "Dato '810015' — Edificación. 1 producto(s) encontrado(s).",
        "data": {
          "dato": {
            "cdDato": 810015,
            "deDato": "Edificación",
            "tpDato": "N",
            "nuLongitud": 13,
            "nuDecimales": 2,
            "cdTabla": null,
            "inUso": 2,
            "cdBusqueda": null,
            "inConsultaSiniestro": 0,
            "inValidaPersona": null,
            "inAsignacionAutomatica": null
          },
          "productos": [
            {
              "version": 6,
              "cdProducto": 550100,
              "nuBienAsegurado": 10,
              "cdDato": 810015,
              "cdGrupo": 1,
              "inDatoRequerido": 0,
              "inLugarUsoDato": 1,
              "vaDefectoDato": "0",
              "inIndexar": 0,
              "inActivo": 1,
              "cdProcedimientoAntes": null,
              "cdProcedimientoDespues": "VALIDA_MAYOR_CERO",
              "nuConsecutivo": 12,
              "cdJavascriptDespues": "DR_BUSCA_VALORES_PP()",
              "inMatrizCertificado": 1,
              "inMostrarSiniestro": 0,
              "inEndoso": 0,
              "inMostrarCertificado": 0,
              "inArrastreValor": 0,
              "inEjecRenovacionProcAnt": 0,
              "inEjecRenovacionProcDesp": 0,
              "inNoMostrarConsultaOtros": 0,
              "inBusquedaSiniestro": 0,
              "inNoMostrarWebExterna": 0,
              "vaDefectoDatoWebExterna": null,
              "inNoMostrarWebMediador": null,
              "vaDefectoDatoWebMediador": null,
              "inDataWarehouse": null,
              "inConsultaTotalizada": null,
              "inInvisibleDefecto": null,
              "inMostrarMercancia": null,
              "cdDatoPadre": null,
              "inEndosoMultiple": null,
              "nmPackageAjax": null,
              "inRecargarDatos": null,
              "inAplicarPoCoaseguro": null,
              "inNoMostrarWebDelegado": null,
              "vaDefectoDatoWebDelegado": null,
              "inNoMostrarEndosoWebMedi": null,
              "inNoMostrarEndosoWebExte": null,
              "inNoMostrarEndosoWebDele": null,
              "deProducto": "Mi Hogar Total"
            }
          ]
        }
      }
      ''';

        final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        final info = DatoInfo.fromJson(data);

        expect(info.cdDato, 810015);
        expect(info.deDato, 'Edificación');
        expect(info.tpDato, 'N');
        expect(info.nuLongitud, 13);
        expect(info.nuDecimales, 2);
        expect(info.productos.length, 1);

        final prod = info.productos.first;
        expect(prod.cdProducto, 550100);
        expect(prod.deProducto, 'Mi Hogar Total');
        expect(prod.version, 6);
        expect(prod.nuBienAsegurado, 10);
        expect(prod.cdProcedimientoDespues, 'VALIDA_MAYOR_CERO');
        expect(prod.cdJavascriptDespues, 'DR_BUSCA_VALORES_PP()');
        expect(prod.inActivo, 1);
      },
    );

    test('Parsea campos adicionales y TablaDefinicionAdicional', () {
      final datoMap = {
        'version': 3,
        'cdDato': 1234,
        'deDato': 'Marca Vehiculo',
        'tpDato': 'A',
        'cdTabla': 8001,
      };
      final dato = DatoInfo.fromJson(datoMap);
      expect(dato.version, 3);
      expect(dato.cdDato, 1234);

      final defMap = {
        'version': 2,
        'cdTabla': 8001,
        'deTabla': 'Marcas',
        'inComboConsulta': 1,
        'nmPackageLlenado': 'PKG_LLENADO',
        'columnas': [
          {'cdDato': 100, 'deDato': 'Marca'},
        ],
      };
      final def = TablaDefinicion.fromJson(defMap);
      expect(def.version, 2);
      expect(def.inComboConsulta, true);
      expect(def.nmPackageLlenado, 'PKG_LLENADO');

      final defAdicMap = {
        'version': 1,
        'cdTabla': 8001,
        'cdDatoAdicional': 999,
        'deDatoAdicional': 'Submarca',
        'cdConsecutivoDatoAdicional': 1,
        'inDatoAdicionalRequerido': 1,
      };
      final defAdic = TablaDefinicionAdicional.fromJson(defAdicMap);
      expect(defAdic.version, 1);
      expect(defAdic.cdTabla, 8001);
      expect(defAdic.cdDatoAdicional, 999);
      expect(defAdic.deDatoAdicional, 'Submarca');
      expect(defAdic.cdConsecutivoDatoAdicional, 1);
      expect(defAdic.inDatoAdicionalRequerido, true);
    });

    test('Filtra productos por código o por descripción correctamente', () {
      final p1 = DatoProducto(
        cdProducto: 550100,
        deProducto: 'Mi Hogar Total',
        raw: const {},
      );
      final p2 = DatoProducto(
        cdProducto: 120500,
        deProducto: 'Automóviles Responsabilidad Civil',
        raw: const {},
      );
      final p3 = DatoProducto(
        cdProducto: 990001,
        deProducto: 'Incendio Comercial',
        raw: const {},
      );
      final lista = [p1, p2, p3];

      List<DatoProducto> filter(String q) {
        final query = q.trim().toLowerCase();
        if (query.isEmpty) return lista;
        return lista.where((p) {
          final cdMatches = p.cdProducto?.toString().toLowerCase().contains(query) ?? false;
          final deMatches = p.deProducto?.toLowerCase().contains(query) ?? false;
          return cdMatches || deMatches;
        }).toList();
      }

      // Filtro por código
      expect(filter('5501').map((e) => e.cdProducto), [550100]);
      expect(filter('1205').map((e) => e.cdProducto), [120500]);

      // Filtro por descripción
      expect(filter('hogar').map((e) => e.cdProducto), [550100]);
      expect(filter('responsabilidad').map((e) => e.cdProducto), [120500]);
      expect(filter('comercial').map((e) => e.cdProducto), [990001]);

      // Búsqueda sin coincidencias
      expect(filter('salud'), isEmpty);

      // Búsqueda vacía devuelve todos
      expect(filter(''), hasLength(3));
    });
  });
}
