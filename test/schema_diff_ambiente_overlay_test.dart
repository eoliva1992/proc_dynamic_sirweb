import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/screens/schema_object_diff_page.dart';

void main() {
  testWidgets('el selector de ambiente funciona con la ventana montada en el '
      'overlay (z-order real)', (tester) async {
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

    // Igual que en la app: ventana flotante en el overlay raíz.
    showSchemaObjectDiff(
      ctx,
      objectName: 'PCK_TEST',
      objectType: 'PACKAGE',
      sourceAmbiente: 'Desa',
    );
    await tester.pumpAndSettle();

    expect(find.text('DESTINO · Demo'), findsOneWidget);

    await tester.tap(find.text('DESTINO · Demo'));
    await tester.pumpAndSettle();

    // El menú debe quedar POR ENCIMA de la ventana y ser clickeable.
    await tester.tap(find.text('QA').last);
    await tester.pumpAndSettle();

    expect(find.text('DESTINO · QA'), findsOneWidget);
  });
}
