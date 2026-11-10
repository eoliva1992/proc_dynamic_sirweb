import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proc_dynamic_sirweb/models/plantilla.dart';
import 'package:proc_dynamic_sirweb/services/plantilla_service.dart';
import 'package:proc_dynamic_sirweb/widgets/new_object_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null;
    PlantillaService.setHttpClientForTesting(
      MockClient((request) async {
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );
  });

  tearDownAll(() {
    PlantillaService.setHttpClientForTesting(null);
  });

  group('NewObjectDialog tests', () {
    test('NewObjectType definitions are complete', () {
      expect(NewObjectType.values.length, 7);
      expect(NewObjectType.function.category, Plantilla.catFunction);
      expect(NewObjectType.procedure.category, Plantilla.catProcedure);
      expect(
        NewObjectType.dynamicProcedure.category,
        Plantilla.catProcDinamico,
      );
      expect(NewObjectType.package.category, Plantilla.catPackage);
      expect(NewObjectType.trigger.category, Plantilla.catTrigger);
      expect(NewObjectType.type.category, Plantilla.catType);
      expect(NewObjectType.blankSql.isBlankDirect, isTrue);
    });

    test(
      'PlantillaService contains seed templates for all standard categories',
      () {
        final plantillas = PlantillaService.plantillasPorDefecto();
        final categories = plantillas.map((p) => p.categoria).toSet();

        expect(categories.contains(Plantilla.catFunction), isTrue);
        expect(categories.contains(Plantilla.catProcedure), isTrue);
        expect(categories.contains(Plantilla.catProcDinamico), isTrue);
        expect(categories.contains(Plantilla.catPackage), isTrue);
        expect(categories.contains(Plantilla.catTrigger), isTrue);
        expect(categories.contains(Plantilla.catType), isTrue);
      },
    );

    testWidgets('Renders Step 1 with all object categories', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      NewObjectResult? result;
      showNewObjectDialog(ctx, ambiente: 'Desa').then((r) => result = r);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Crear Nuevo Objeto o Documento'), findsOneWidget);
      expect(
        find.text('Paso 1: ¿Qué tipo de objeto deseas crear?'),
        findsOneWidget,
      );
      expect(find.text('Nueva Función'), findsOneWidget);
      expect(find.text('Nuevo Procedimiento'), findsOneWidget);
      expect(find.text('Nuevo Procedimiento Dinámico'), findsOneWidget);
      expect(find.text('Nuevo Package'), findsOneWidget);
      expect(find.text('Nuevo Trigger'), findsOneWidget);
      expect(find.text('Nuevo Type'), findsOneWidget);
      expect(find.text('Documento en blanco (SQL)'), findsOneWidget);

      // Doble click / doble tap en la tarjeta de Procedimiento Dinámico
      await tester.tap(find.text('Nuevo Procedimiento Dinámico'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Nuevo Procedimiento Dinámico'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(result, isA<NewDynamicProcedureAction>());
    });

    testWidgets(
      'Selecting Blank SQL directly returns OpenBlankSqlSheetAction',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );

        NewObjectResult? result;
        showNewObjectDialog(ctx, ambiente: 'QA').then((r) => result = r);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Doble click / doble tap en la tarjeta de Documento en blanco (SQL)
        await tester.tap(find.text('Documento en blanco (SQL)'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Documento en blanco (SQL)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(result, isA<OpenBlankSqlSheetAction>());
        expect((result as OpenBlankSqlSheetAction).ambiente, 'QA');
      },
    );

    testWidgets(
      'Navigates to Step 2 for Function and confirms template selection',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );

        NewObjectResult? result;
        showNewObjectDialog(
          ctx,
          ambiente: 'Desa',
          initialType: NewObjectType.function,
        ).then((r) => result = r);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // Completar microtareas del FutureBuilder sin esperar indefinidamente animaciones de progreso
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Debería arrancar en el paso 2 porque se envió initialType
        expect(
          find.text('Paso 2: Plantillas para Nueva Función'),
          findsOneWidget,
        );
        expect(find.text('VISTA PREVIA DEL CÓDIGO'), findsOneWidget);
        expect(find.text('Abrir en Editor SQL'), findsOneWidget);

        await tester.tap(find.text('Abrir en Editor SQL'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(result, isA<OpenInSqlEditorAction>());
        final action = result as OpenInSqlEditorAction;
        expect(action.code.isNotEmpty, isTrue);
        expect(action.ambiente, 'Desa');
        expect(action.snippetCode != null, isTrue);
        // Debe conservar tabstops interactivos como ${1:nombre} en el snippetCode
        expect(action.snippetCode!.contains(r'${1:nombre}'), isTrue);
      },
    );
  });
}
