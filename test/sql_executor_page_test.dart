import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/screens/sql_executor_page.dart';

/// El editor Monaco usa un WebView real (webview_flutter_windows) que nunca
/// se asienta en `flutter_test`; por eso evitamos `pumpAndSettle` y usamos un
/// bucle acotado de `pump`. Ver /memories/repo/testing_flutter_monaco.md.
Future<void> _pumpBounded(WidgetTester tester, {int times = 15}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<void> setLargeSurface(WidgetTester tester) async {
    final view = tester.view;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  testWidgets(
    'muestra el chip del tipo de sentencia (DML) para el SQL inicial',
    (tester) async {
      await setLargeSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlExecutorPage(
              ambiente: 'DES',
              onAmbienteChanged: (_) {},
              initialSql: "INSERT INTO CLIENTE (ID) VALUES (1);",
            ),
          ),
        ),
      );
      await _pumpBounded(tester);

      expect(find.text('DML'), findsOneWidget);
      expect(
        find.byTooltip('Ejecutar sentencia actual / selección (Ctrl+Enter)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('la salida inicia visible y puede colapsarse y reabrirse', (
    tester,
  ) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SqlExecutorPage(
            ambiente: 'DES',
            onAmbienteChanged: (_) {},
            initialSql: 'SELECT 1 FROM dual;',
          ),
        ),
      ),
    );
    await _pumpBounded(tester);

    expect(find.text('Salida'), findsOneWidget);
    await tester.tap(find.byTooltip('Colapsar salida'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mostrar salida'), findsOneWidget);

    await tester.tap(find.text('Mostrar salida'));
    await _pumpBounded(tester, times: 4);
    expect(find.text('Salida'), findsOneWidget);
  });
}
