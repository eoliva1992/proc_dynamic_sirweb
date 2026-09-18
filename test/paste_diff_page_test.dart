import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/screens/paste_diff_page.dart';
import 'package:proc_dynamic_sirweb/widgets/native_diff_viewer.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // MonacoEditor muestra un indicador de carga que anima indefinidamente en
  // el entorno de pruebas (no hay WebView2 real), por lo que
  // `pumpAndSettle` nunca se estabiliza. Usamos un número acotado de pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openPage(
    WidgetTester tester, {
    String initialSource = '',
    String initialTarget = '',
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PasteDiffPage(
          initialSource: initialSource,
          initialTarget: initialTarget,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> openModal(
    WidgetTester tester, {
    required String source,
    required String target,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showPasteDiff(
                context,
                initialSource: source,
                initialTarget: target,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await settle(tester);
  }

  testWidgets('muestra dos editores y el visor de comparación', (tester) async {
    await openPage(tester);

    expect(find.text('Origen'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
    expect(find.text('Comparación'), findsOneWidget);
    expect(find.byKey(const ValueKey('origen-editor-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('destino-editor-panel')), findsOneWidget);
  });

  testWidgets('edita ambos paneles y actualiza el diff', (tester) async {
    await openPage(
      tester,
      initialSource: 'BEGIN\n  NULL;\nEND;',
      initialTarget: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.textContaining('3 / 3 líneas'), findsOneWidget);
    expect(find.byType(NativeDiffViewer), findsOneWidget);
    expect(find.text('Hay diferencias'), findsWidgets);
  });

  testWidgets('permite colapsar y restaurar los editores de fuentes', (
    tester,
  ) async {
    await openPage(tester);

    expect(find.byKey(const ValueKey('origen-editor-panel')), findsOneWidget);
    await tester.tap(find.byTooltip('Ocultar fuentes'));
    await settle(tester);

    expect(find.text('Fuentes ocultas'), findsOneWidget);
    expect(find.byKey(const ValueKey('origen-editor-panel')), findsNothing);
    expect(find.byType(NativeDiffViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Mostrar fuentes'));
    await settle(tester);
    expect(find.byKey(const ValueKey('origen-editor-panel')), findsOneWidget);
  });

  testWidgets('abre como modal y aplica todo al destino con confirmación', (
    tester,
  ) async {
    await openModal(tester, source: 'A\nB', target: 'A\nX');

    expect(find.text('Diff pegado'), findsOneWidget);
    expect(find.text('Hay diferencias'), findsWidgets);
    await tester.tap(find.text('Aplicar todo al destino'));
    await settle(tester);
    expect(find.text('Reemplazar todo el destino'), findsOneWidget);
    await tester.tap(find.text('Reemplazar'));
    await settle(tester);

    expect(find.text('Sin cambios'), findsWidgets);
  });

  testWidgets('aplica todo al origen y permite deshacer', (tester) async {
    await openModal(tester, source: 'A\nB', target: 'A\nX');

    await tester.tap(find.text('Aplicar todo al origen'));
    await settle(tester);
    await tester.tap(find.text('Reemplazar'));
    await settle(tester);

    expect(find.text('Sin cambios'), findsWidgets);

    await tester.tap(find.byTooltip('Deshacer'));
    await settle(tester);
    expect(find.text('Hay diferencias'), findsWidgets);
  });
}
