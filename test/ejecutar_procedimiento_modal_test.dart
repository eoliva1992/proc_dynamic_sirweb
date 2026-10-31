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
}
