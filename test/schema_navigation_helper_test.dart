import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/services/schema_navigation_helper.dart';
import 'package:proc_dynamic_sirweb/services/schema_service.dart';

void main() {
  group('findSchemaObjectInMetadata', () {
    const mockSchema = SchemaMetadata(
      tables: ['CLIENTE', 'POLIZA', 'ORDEN_PAGO'],
      views: ['VW_CLIENTES_ACTIVOS', 'VW_RESUMEN_POLIZA'],
      objects: [
        (name: 'PR_CALCULAR_PRIMA', type: 'PROCEDURE', owner: 'DESA'),
        (name: 'FN_OBTENER_DESCUENTO', type: 'FUNCTION', owner: 'DESA'),
        (name: 'PKG_COTIZADOR', type: 'PACKAGE', owner: 'DESA'),
        (name: 'T_OBJ_CLIENTE', type: 'TYPE', owner: 'DESA'),
        (name: 'T_TAB_ITEMS', type: 'TYPE', owner: 'DESA'),
      ],
    );

    test('resuelve tablas simples', () {
      final res = findSchemaObjectInMetadata('cliente', mockSchema);
      expect(res, isNotNull);
      expect(res!.name, 'CLIENTE');
      expect(res.objectType, 'TABLE');
    });

    test('resuelve vistas', () {
      final res = findSchemaObjectInMetadata('VW_CLIENTES_ACTIVOS', mockSchema);
      expect(res, isNotNull);
      expect(res!.name, 'VW_CLIENTES_ACTIVOS');
      expect(res.objectType, 'VIEW');
    });

    test('resuelve procedimientos', () {
      final res = findSchemaObjectInMetadata('pr_calcular_prima', mockSchema);
      expect(res, isNotNull);
      expect(res!.name, 'PR_CALCULAR_PRIMA');
      expect(res.objectType, 'PROCEDURE');
    });

    test('resuelve funciones', () {
      final res = findSchemaObjectInMetadata(
        'fn_obtener_descuento',
        mockSchema,
      );
      expect(res, isNotNull);
      expect(res!.name, 'FN_OBTENER_DESCUENTO');
      expect(res.objectType, 'FUNCTION');
    });

    test('resuelve paquetes', () {
      final res = findSchemaObjectInMetadata('pkg_cotizador', mockSchema);
      expect(res, isNotNull);
      expect(res!.name, 'PKG_COTIZADOR');
      expect(res.objectType, 'PACKAGE');
    });

    test('resuelve types', () {
      final res = findSchemaObjectInMetadata('t_obj_cliente', mockSchema);
      expect(res, isNotNull);
      expect(res!.name, 'T_OBJ_CLIENTE');
      expect(res.objectType, 'TYPE');
    });

    test('resuelve nombres calificados por owner (SCHEMA.TABLE)', () {
      final res = findSchemaObjectInMetadata('DESA.ORDEN_PAGO', mockSchema);
      expect(res, isNotNull);
      expect(res!.name, 'ORDEN_PAGO');
      expect(res.objectType, 'TABLE');
    });

    test('resuelve llamadas a paquetes (PACKAGE.SUBPROGRAM)', () {
      final res = findSchemaObjectInMetadata(
        'PKG_COTIZADOR.EMITIR',
        mockSchema,
      );
      expect(res, isNotNull);
      expect(res!.name, 'PKG_COTIZADOR');
      expect(res.objectType, 'PACKAGE');
    });

    test('retorna null para identificadores no existentes', () {
      final res = findSchemaObjectInMetadata(
        'VARIABLE_INEXISTENTE',
        mockSchema,
      );
      expect(res, isNull);
    });
  });
}
