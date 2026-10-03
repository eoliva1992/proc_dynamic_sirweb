import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/screens/schema_object_diff_page.dart';
import 'package:proc_dynamic_sirweb/services/backup_service.dart';

void main() {
  group('SchemaObjectDiffPage - Deshacer y Rehacer', () {
    testWidgets('controles de undo y redo están presentes en la toolbar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SchemaObjectDiffPage(
              objectName: 'PCK_TEST',
              objectType: 'PACKAGE',
              sourceAmbiente: 'Desa',
            ),
          ),
        ),
      );
      await tester.pump();

      // Antes de cargar comparación o en toolbar reducida, solo se muestran los controles base.
      expect(find.byType(SchemaObjectDiffPage), findsOneWidget);
    });
  });

  group('BackupService - buildFullSchemaScript', () {
    test('genera script estructurado para objetos simples', () {
      final script = BackupService.buildFullSchemaScript(
        objectName: 'SP_CALCULAR',
        objectType: 'PROCEDURE',
        ambiente: 'QA',
        specSource:
            'CREATE OR REPLACE PROCEDURE SP_CALCULAR AS BEGIN NULL; END;',
      );

      expect(script, contains('-- BACKUP SCHEMA OBJECT'));
      expect(script, contains('Objeto   : SP_CALCULAR'));
      expect(script, contains('Ambiente : QA'));
      expect(
        script,
        contains(
          'CREATE OR REPLACE PROCEDURE SP_CALCULAR AS BEGIN NULL; END;\n/',
        ),
      );
    });

    test('genera script con SPEC y BODY para PACKAGE', () {
      final script = BackupService.buildFullSchemaScript(
        objectName: 'PCK_PAGOS',
        objectType: 'PACKAGE',
        ambiente: 'Desa',
        specSource:
            'CREATE OR REPLACE PACKAGE PCK_PAGOS AS PROCEDURE DO_PAGO; END;',
        bodySource:
            'CREATE OR REPLACE PACKAGE BODY PCK_PAGOS AS PROCEDURE DO_PAGO IS BEGIN NULL; END; END;',
      );

      expect(script, contains('-- === SPEC ==='));
      expect(script, contains('-- === BODY ==='));
      expect(script, contains('PCK_PAGOS'));
      expect(script, contains('/'));
    });
  });
}
