import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/screens/schema_object_diff_page.dart';
import 'package:proc_dynamic_sirweb/widgets/floating_window.dart';

void main() {
  testWidgets('los controles de ventana quedan pegados a la esquina superior '
      'derecha de la ventana flotante', (tester) async {
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

    final windowRect = tester.getRect(find.byType(AnimatedPositioned).first);

    // Se esperan 3 controles: minimizar, maximizar y cerrar.
    final buttons = find.byType(WindowButton);
    expect(buttons, findsNWidgets(3));

    // El último (cerrar) debe tocar el borde derecho y el superior.
    final closeRect = tester.getRect(buttons.last);
    expect(
      windowRect.right - closeRect.right,
      lessThanOrEqualTo(1.0),
      reason: 'El botón de cerrar debe estar pegado al borde derecho',
    );
    expect(
      closeRect.top - windowRect.top,
      lessThanOrEqualTo(1.0),
      reason: 'El botón de cerrar debe estar pegado al borde superior',
    );

    // Los tres botones deben ser contiguos, sin separación entre ellos.
    final minRect = tester.getRect(buttons.at(0));
    final maxRect = tester.getRect(buttons.at(1));
    expect(maxRect.left - minRect.right, closeTo(0, 0.5));
    expect(closeRect.left - maxRect.right, closeTo(0, 0.5));
  });

  testWidgets('permite cambiar el ambiente destino desde la toolbar', (
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

    // Estado inicial: ORIGEN Desa vs DESTINO Demo (primer ambiente distinto).
    expect(find.text('ORIGEN · Desa'), findsOneWidget);
    expect(find.text('DESTINO · Demo'), findsOneWidget);

    // Abrir el selector del destino y elegir QA.
    await tester.tap(find.text('DESTINO · Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA').last);
    await tester.pumpAndSettle();

    expect(find.text('DESTINO · QA'), findsOneWidget);
    expect(find.text('ORIGEN · Desa'), findsOneWidget);
  });

  testWidgets('elegir en destino el ambiente del origen los intercambia', (
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

    await tester.tap(find.text('DESTINO · Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desa').last);
    await tester.pumpAndSettle();

    // Nunca se compara un ambiente contra sí mismo: se intercambian.
    expect(find.text('DESTINO · Desa'), findsOneWidget);
    expect(find.text('ORIGEN · Demo'), findsOneWidget);
  });
}
