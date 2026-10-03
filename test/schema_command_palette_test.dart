import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/services/schema_recents_service.dart';
import 'package:proc_dynamic_sirweb/widgets/schema_command_palette.dart';
import 'package:proc_dynamic_sirweb/widgets/source_tab_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    SourceTabController.unregisterGlobal(
      ({
        required String name,
        required String objectType,
        required String ambiente,
        int? initialLine,
        String? initialSearchTerm,
      }) {},
    );
  });

  Widget buildHost({required String ambiente}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  showSchemaCommandPalette(context, ambiente: ambiente);
                },
                child: const Text('Abrir Paleta'),
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets(
    'muestra icono de ver fuente en resultados recientes y abre fuente',
    (tester) async {
      final openedCalls = <Map<String, dynamic>>[];
      SourceTabController.registerGlobal(({
        required String name,
        required String objectType,
        required String ambiente,
        int? initialLine,
        String? initialSearchTerm,
      }) {
        openedCalls.add({
          'name': name,
          'objectType': objectType,
          'ambiente': ambiente,
          'initialLine': initialLine,
          'initialSearchTerm': initialSearchTerm,
        });
      });

      await SchemaRecentsService.instance.addRecent(
        const SchemaObjectRef(
          name: 'PCK_FACTURACION',
          type: 'PACKAGE',
          ambiente: 'Desa',
          owner: 'SIR',
        ),
      );

      await tester.pumpWidget(buildHost(ambiente: 'Desa'));
      await tester.tap(find.text('Abrir Paleta'));
      await tester.pumpAndSettle();

      expect(find.text('PCK_FACTURACION'), findsOneWidget);
      expect(find.byTooltip('Ver fuente'), findsOneWidget);
      expect(find.byTooltip('Ejecutar (Ctrl+Shift+E)'), findsOneWidget);

      await tester.tap(find.byTooltip('Ver fuente'));
      await tester.pumpAndSettle();

      expect(openedCalls.length, equals(1));
      expect(openedCalls.first['name'], equals('PCK_FACTURACION'));
      expect(openedCalls.first['objectType'], equals('PACKAGE'));
      expect(openedCalls.first['ambiente'], equals('Desa'));
      expect(find.text('PCK_FACTURACION'), findsNothing);
    },
  );

  testWidgets(
    'limpiar recientes solicita confirmacion y vacia solo los del ambiente actual',
    (tester) async {
      await SchemaRecentsService.instance.addRecent(
        const SchemaObjectRef(
          name: 'TABLA_LOCAL',
          type: 'TABLE',
          ambiente: 'Desa',
        ),
      );
      await SchemaRecentsService.instance.addRecent(
        const SchemaObjectRef(
          name: 'TABLA_PROD',
          type: 'TABLE',
          ambiente: 'Prod',
        ),
      );

      await tester.pumpWidget(buildHost(ambiente: 'Desa'));
      await tester.tap(find.text('Abrir Paleta'));
      await tester.pumpAndSettle();

      expect(find.text('TABLA_LOCAL'), findsOneWidget);
      final clearButton = find.byTooltip('Limpiar recientes');
      expect(clearButton, findsOneWidget);

      // 1. Cancelar
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '¿Eliminar todo el historial de recientes del ambiente actual?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('TABLA_LOCAL'), findsOneWidget);
      final recentsDesaAfterCancel = await SchemaRecentsService.instance
          .getRecents(ambiente: 'Desa');
      expect(recentsDesaAfterCancel.length, equals(1));

      // 2. Confirmar eliminación
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('TABLA_LOCAL'), findsNothing);
      expect(find.text('Sin objetos visitados recientemente'), findsOneWidget);

      final recentsDesa = await SchemaRecentsService.instance.getRecents(
        ambiente: 'Desa',
      );
      final recentsProd = await SchemaRecentsService.instance.getRecents(
        ambiente: 'Prod',
      );
      expect(recentsDesa, isEmpty);
      expect(recentsProd.length, equals(1));
      expect(recentsProd.first.name, equals('TABLA_PROD'));
    },
  );

  testWidgets('notifica version de recientes a oyentes externos al limpiar', (
    tester,
  ) async {
    int notifications = 0;
    void listener() => notifications++;
    SchemaRecentsService.instance.recentsVersion.addListener(listener);

    await SchemaRecentsService.instance.addRecent(
      const SchemaObjectRef(name: 'V_CLIENTES', type: 'VIEW', ambiente: 'QA'),
    );
    expect(notifications, equals(1));

    await SchemaRecentsService.instance.clearRecents(ambiente: 'QA');
    expect(notifications, equals(2));

    SchemaRecentsService.instance.recentsVersion.removeListener(listener);
  });
}
