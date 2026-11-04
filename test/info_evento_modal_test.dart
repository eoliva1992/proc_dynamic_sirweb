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
    'showInfoEventoWindow muestra UI de búsqueda y maneja estado inicial',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      final ctx = rootNavigatorKey.currentContext!;

      showInfoEventoWindow(ctx, 'EVT_PRUEBA', 'Desa');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Información de Evento'), findsOneWidget);
      expect(find.text('EVT_PRUEBA'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Top: '), findsOneWidget);
    },
  );
}
