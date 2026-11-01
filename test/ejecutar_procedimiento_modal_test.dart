import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/widgets/code_editor_panel.dart';

void main() {
  Widget app() => MaterialApp(
    navigatorKey: rootNavigatorKey,
    home: const Scaffold(body: SizedBox.expand()),
  );

  testWidgets(
    'showEjecutarProcedimientoWindow inicia cdEntidad en 30 y muestra P_CD_DATO para config D',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      final ctx = rootNavigatorKey.currentContext!;

      showEjecutarProcedimientoWindow(
        ctx,
        'DR_TEST_DATO',
        'Desa',
        inConfiguracion: 'D',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('DR_TEST_DATO'), findsOneWidget);
      expect(find.text('CD_ENTIDAD'), findsOneWidget);
      expect(find.text('30'), findsWidgets);

      // Desplazamos la lista hacia arriba para encontrar P_CD_DATO
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Debe mostrar el campo específico P_CD_DATO para inConfiguracion: 'D'
      expect(find.text('P_CD_DATO'), findsOneWidget);
    },
  );

  testWidgets(
    'showEjecutarProcedimientoWindow NO muestra P_CD_DATO cuando inConfiguracion no es D',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      final ctx = rootNavigatorKey.currentContext!;

      showEjecutarProcedimientoWindow(
        ctx,
        'DR_TEST_COTI',
        'Desa',
        inConfiguracion: 'C',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('DR_TEST_COTI'), findsOneWidget);
      expect(find.text('CD_ENTIDAD'), findsOneWidget);
      expect(find.text('30'), findsWidgets);

      // No debe mostrar P_CD_DATO para config C
      expect(find.text('P_CD_DATO'), findsNothing);
    },
  );

  testWidgets(
    'pestaña HTTP está disponible antes de ejecutar y muestra previsualización del request',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      final ctx = rootNavigatorKey.currentContext!;

      showEjecutarProcedimientoWindow(
        ctx,
        'DR_TEST_HTTP',
        'Desa',
        inConfiguracion: 'C',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // La pestaña HTTP debe ser visible desde el inicio con su contador
      final httpTabFinder = find.text('HTTP (1)');
      expect(httpTabFinder, findsOneWidget);

      // Desplazamos la fila de pestañas si es necesario y hacemos tap centrado
      await tester.ensureVisible(httpTabFinder);
      await tester.tap(httpTabFinder);
      await tester.pumpAndSettle();

      // Debe mostrar el badge de PREVIEW y la URL
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);
      expect(
        find.textContaining(
          'tools/procedimiento-dinamico/DR_TEST_HTTP/ejecutar',
        ),
        findsWidgets,
      );
      expect(find.textContaining('COMANDO CURL'), findsOneWidget);
      expect(
        find.textContaining(
          'Previsualización de la petición HTTP antes de ejecutar',
        ),
        findsOneWidget,
      );
      expect(find.text('CD_ENTIDAD'), findsWidgets);
    },
  );

  testWidgets(
    'showEjecutarProcedimientoWindow mantiene accesible pestaña HTTP ante errores de ejecución',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      final ctx = rootNavigatorKey.currentContext!;

      showEjecutarProcedimientoWindow(
        ctx,
        'DR_TEST_ERR',
        'Desa',
        inConfiguracion: 'C',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final httpTabFinder = find.text('HTTP (1)');
      expect(httpTabFinder, findsOneWidget);
      await tester.ensureVisible(httpTabFinder);
      await tester.tap(httpTabFinder);
      await tester.pumpAndSettle();

      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.byType(ListView), findsWidgets);
    },
  );
}
