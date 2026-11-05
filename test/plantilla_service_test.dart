import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/plantilla.dart';
import 'package:proc_dynamic_sirweb/services/plantilla_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  group('Plantilla Model', () {
    test('Serialización y deserialización JSON', () {
      final p = Plantilla(
        id: 'pl-100',
        nombre: 'Mi Plantilla Test',
        categoria: Plantilla.catProcedure,
        contenido: 'CREATE OR REPLACE PROCEDURE {NOMBRE} IS BEGIN NULL; END;',
        descripcion: 'Plantilla de prueba unitaria',
        ownerUser: 'TEST_USER',
        isActive: true,
        version: 1,
      );

      final json = p.toUpdateJson();
      expect(json['id'], 'pl-100');
      expect(json['nombre'], 'Mi Plantilla Test');
      expect(json['categoria'], Plantilla.catProcedure);

      final fromJson = Plantilla.fromJson(json);
      expect(fromJson.id, 'pl-100');
      expect(fromJson.nombre, 'Mi Plantilla Test');
      expect(fromJson.categoria, Plantilla.catProcedure);
      expect(fromJson.isActive, isTrue);
    });

    test('Aplicar parámetros y sustitución de tokens', () {
      const p = Plantilla(
        id: '1',
        nombre: 'Test',
        categoria: Plantilla.catProcDinamico,
        contenido: 'PROC: {NOMBRE_PROC} por {USUARIO} en {FECHA}',
      );

      final codigo = p.aplicarParametros(
        nombreObjeto: 'PROC_CLIENTES',
        usuario: 'DEVELOPER',
      );

      expect(codigo.contains('PROC_CLIENTES'), isTrue);
      expect(codigo.contains('DEVELOPER'), isTrue);
      expect(codigo.contains('{NOMBRE_PROC}'), isFalse);
    });

    test('Búsqueda local matches()', () {
      const p = Plantilla(
        id: '1',
        nombre: 'Procedimiento Auditoría',
        categoria: Plantilla.catProcedure,
        contenido: 'SELECT 1 FROM DUAL;',
        descripcion: 'Registra logs de auditoría',
      );

      expect(p.matches('auditoría'), isTrue);
      expect(p.matches('PROCEDURE'), isTrue);
      expect(p.matches('SELECT'), isTrue);
      expect(p.matches('inexistente'), isFalse);
    });
  });

  group('PlantillaService Fallback y Seeds', () {
    test('Retorna plantillas por defecto cuando no hay conexión', () {
      final seeds = PlantillaService.plantillasPorDefecto();
      expect(seeds.isNotEmpty, isTrue);
      expect(seeds.any((s) => s.categoria == Plantilla.catProcDinamico), isTrue);
      expect(seeds.any((s) => s.categoria == Plantilla.catProcedure), isTrue);
      expect(seeds.any((s) => s.categoria == Plantilla.catFunction), isTrue);
      expect(seeds.any((s) => s.categoria == Plantilla.catPackage), isTrue);
    });
  });
}
