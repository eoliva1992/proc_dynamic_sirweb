import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/services/schema_service.dart';
import 'package:proc_dynamic_sirweb/widgets/definition_navigation.dart';
import 'package:proc_dynamic_sirweb/widgets/source_tab_controller.dart';

void main() {
  group('DynamicProcedureTabController', () {
    testWidgets('registra y desregistra el handler global correctamente', (
      tester,
    ) async {
      String? openedProc;
      String? openedAmbiente;

      void dummyHandler({
        required String cdProcedimiento,
        required String ambiente,
      }) {
        openedProc = cdProcedimiento;
        openedAmbiente = ambiente;
      }

      DynamicProcedureTabController.registerGlobal(dummyHandler);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final handler = DynamicProcedureTabController.openTabOf(context);
              expect(handler, isNotNull);
              handler?.call(cdProcedimiento: 'DR_PRUEBA', ambiente: 'Desa');
              return const SizedBox();
            },
          ),
        ),
      );

      expect(openedProc, 'DR_PRUEBA');
      expect(openedAmbiente, 'Desa');

      DynamicProcedureTabController.unregisterGlobal(dummyHandler);
    });
  });

  group('navigateToDefinition con procedimiento dinámico en memoria', () {
    const testProc = Procedimiento(
      cdProcedimiento: 'DR_CALCULO_PRUEBA',
      deTexto: 'BEGIN NULL; END;',
      inConfiguracion: 'P',
      version: 1,
      stProcedimiento: '1',
    );

    const emptySchema = SchemaMetadata(
      tables: [],
      views: [],
      objects: [],
    );

    setUp(() {
      SchemaService.instance.overrideCacheForTesting('Desa', emptySchema);
      procedimientosProvider.procedimientoActual = testProc;
    });

    tearDown(() {
      procedimientosProvider.procedimientoActual = null;
    });

    testWidgets('abre procedimiento dinámico si coincide con el actual', (
      tester,
    ) async {
      String? targetProc;
      String? targetAmbiente;

      void handler({
        required String cdProcedimiento,
        required String ambiente,
      }) {
        targetProc = cdProcedimiento;
        targetAmbiente = ambiente;
      }

      DynamicProcedureTabController.registerGlobal(handler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    navigateToDefinition(
                      context,
                      'dr_calculo_prueba',
                      ambiente: 'Desa',
                    );
                  },
                  child: const Text('Go'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(targetProc, 'DR_CALCULO_PRUEBA');
      expect(targetAmbiente, 'Desa');

      DynamicProcedureTabController.unregisterGlobal(handler);
    });
  });
}

