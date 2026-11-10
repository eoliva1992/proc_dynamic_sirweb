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
        modifiedBy: 'MODIFIER_USER',
        isActive: true,
        version: 1,
      );

      final json = p.toUpdateJson();
      expect(json['id'], 'pl-100');
      expect(json['nombre'], 'Mi Plantilla Test');
      expect(json['categoria'], Plantilla.catProcedure);
      expect(json['modifiedBy'], 'MODIFIER_USER');
      expect(json['version'], 1);

      final fromJson = Plantilla.fromJson(json);
      expect(fromJson.id, 'pl-100');
      expect(fromJson.nombre, 'Mi Plantilla Test');
      expect(fromJson.categoria, Plantilla.catProcedure);
      expect(fromJson.modifiedBy, 'MODIFIER_USER');
      expect(fromJson.isActive, isTrue);
    });

    test('toUpdateJson genera modifiedBy y version >= 1 por defecto', () {
      const p = Plantilla(
        id: 'pl-200',
        nombre: 'Plantilla Sin Version',
        categoria: Plantilla.catProcedure,
        contenido: 'SELECT 1 FROM DUAL;',
        ownerUser: 'CREATOR',
      );

      final json = p.toUpdateJson(modifiedByUser: 'CURRENT_USER');
      expect(json['modifiedBy'], 'CURRENT_USER');
      expect(json['version'], 1);
    });

    test('Aplicar parámetros y sustitución de tokens (sintaxis snippet)', () {
      const p = Plantilla(
        id: '1',
        nombre: 'Test',
        categoria: Plantilla.catProcDinamico,
        contenido:
            'PROC: \${1:nombre_proc} por \${0:usuario} en \${2:fecha} con \${3:defval}',
      );

      final codigo = p.aplicarParametros(
        nombreObjeto: 'PROC_CLIENTES',
        usuario: 'DEVELOPER',
      );

      expect(codigo.contains('PROC_CLIENTES'), isTrue);
      expect(codigo.contains('DEVELOPER'), isTrue);
      expect(codigo.contains('defval'), isTrue);
      expect(codigo.contains(r'${1:nombre_proc}'), isFalse);
      expect(codigo.contains(r'${0:usuario}'), isFalse);
    });

    test('prepararParaInsercionSnippet conserva tabstops desconocidos', () {
      const p = Plantilla(
        id: '2',
        nombre: 'Test Snippet',
        categoria: Plantilla.catProcedure,
        contenido:
            'CREATE PROCEDURE \${1:nombre} (\${2:p_id} NUMBER) IS BEGIN \$0 END \${1:nombre};',
      );

      final snippet = p.prepararParaInsercionSnippet(
        nombreObjeto: 'SP_CLIENTES',
        usuario: 'ADMIN',
      );

      expect(snippet.contains('SP_CLIENTES'), isTrue);
      expect(snippet.contains(r'${2:p_id}'), isTrue);
      expect(snippet.contains(r'$0'), isTrue);
    });

    test(
      r'prepararParaInsercionSnippet preserva ${1:nombre} si no se da nombreObjeto pero reemplaza usuario y fecha',
      () {
        const p = Plantilla(
          id: '3',
          nombre: 'Test Template',
          categoria: Plantilla.catProcedure,
          contenido:
              '-- Autor: \${0:usuario} | Fecha: \${2:fecha}\n'
              'CREATE PROCEDURE \${1:nombre} (\${3:p_id} NUMBER) IS BEGIN \$0 END \${1:nombre};',
        );

        final snippet = p.prepararParaInsercionSnippet(usuario: 'DEVELOPER');

        expect(snippet.contains('DEVELOPER'), isTrue);
        expect(snippet.contains(r'${0:usuario}'), isFalse);
        expect(snippet.contains(r'${2:fecha}'), isFalse);
        // Mantiene tabstops interactivos para navegación con Tab
        expect(snippet.contains(r'${1:nombre}'), isTrue);
        expect(snippet.contains(r'${3:p_id}'), isTrue);
        expect(snippet.contains(r'$0'), isTrue);
        expect(p.tieneSintaxisSnippet, isTrue);
      },
    );

    test(
      'Reemplazo de sysdate en formatos variables {sysdate: formato}, {sysdate}, etc.',
      () {
        final now = DateTime.now();
        final yyyy = now.year.toString().padLeft(4, '0');
        final mm = now.month.toString().padLeft(2, '0');
        final dd = now.day.toString().padLeft(2, '0');
        final ddmmyyyy = '$dd/$mm/$yyyy';
        final yyyymmdd = '$yyyy-$mm-$dd';

        const p = Plantilla(
          id: '4',
          nombre: 'Sysdate test',
          categoria: Plantilla.catProcedure,
          contenido:
              '-- Creado: {sysdate: dd/mm/yyyy} o {SYSDATE: yyyy-mm-dd} o {SYSDATE} o \${sysdate: yyyy-mm-dd}\n'
              'CREATE PROCEDURE \${1:nombre} IS BEGIN \$0 END;',
        );

        final codigoPlano = p.aplicarParametros();
        expect(codigoPlano.contains(ddmmyyyy), isTrue);
        expect(codigoPlano.contains(yyyymmdd), isTrue);
        expect(codigoPlano.contains('{sysdate: dd/mm/yyyy}'), isFalse);
        expect(codigoPlano.contains('{SYSDATE: yyyy-mm-dd}'), isFalse);
        expect(codigoPlano.contains('{SYSDATE}'), isFalse);

        final snippet = p.prepararParaInsercionSnippet();
        expect(snippet.contains(ddmmyyyy), isTrue);
        expect(snippet.contains(yyyymmdd), isTrue);
        expect(snippet.contains('{sysdate: dd/mm/yyyy}'), isFalse);
        expect(snippet.contains(r'${1:nombre}'), isTrue);
      },
    );

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
      expect(
        seeds.any((s) => s.categoria == Plantilla.catProcDinamico),
        isTrue,
      );
      expect(seeds.any((s) => s.categoria == Plantilla.catProcedure), isTrue);
      expect(seeds.any((s) => s.categoria == Plantilla.catFunction), isTrue);
      expect(seeds.any((s) => s.categoria == Plantilla.catPackage), isTrue);
    });

    test('Filtrado compatible con configuración (SQL vs JS)', () {
      final seeds = PlantillaService.plantillasPorDefecto();
      final jsCompatibles = seeds
          .where((s) => s.esCompatibleConConfig(isJs: true))
          .toList();
      final sqlCompatibles = seeds
          .where((s) => s.esCompatibleConConfig(isJs: false))
          .toList();

      expect(
        jsCompatibles.every((p) => p.monacoLanguage == 'javascript'),
        isTrue,
      );
      expect(sqlCompatibles.every((p) => p.monacoLanguage == 'sql'), isTrue);
      expect(jsCompatibles.any((p) => p.id == 'seed-proc-dinamico-js'), isTrue);
      expect(
        sqlCompatibles.any((p) => p.id == 'seed-proc-dinamico-std'),
        isTrue,
      );
    });

    test('Validación de esPropietario', () {
      const p1 = Plantilla(
        id: 'p1',
        nombre: 'Mi plantilla',
        categoria: Plantilla.catProcedure,
        contenido: 'null',
        ownerUser: 'EOLIVA',
      );

      expect(p1.esPropietario('EOLIVA'), isTrue);
      expect(p1.esPropietario('eoliva'), isTrue);
      expect(p1.esPropietario('OTRO_USER'), isFalse);

      const pAbierta = Plantilla(
        id: 'p2',
        nombre: 'Plantilla sin owner',
        categoria: Plantilla.catProcedure,
        contenido: 'null',
        ownerUser: '',
      );
      expect(pAbierta.esPropietario('EOLIVA'), isTrue);
    });
  });
}
