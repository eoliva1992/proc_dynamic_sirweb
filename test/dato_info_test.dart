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
  });
}
