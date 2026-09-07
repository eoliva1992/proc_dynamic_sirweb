import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/native_diff_viewer.dart';
import 'package:proc_dynamic_sirweb/widgets/procedure_diff_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openDiff(
  WidgetTester tester, {
  required String original,
  required String modified,
  Size windowSize = const Size(1400, 900),
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showProcedureDiff(
                context,
                title: 'Diff — DR_TEST',
                original: original,
                modified: modified,
                language: 'sql',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  const base = 'BEGIN\n  NULL;\nEND;';

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('muestra estadísticas y navegación de hunks', (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    // Badge de lenguaje + estadísticas de líneas
    expect(find.text('SQL'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);

    // Contador de hunks estilo "1 / N" (paridad con el diff de fuentes)
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('inicia en vista completa y unificada', (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.text('Completo'), findsOneWidget);
    expect(find.text('Unificada'), findsOneWidget);
  });

  testWidgets('permite alternar vista dividida/unificada y solo diffs/completo',
      (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.text('Unificada'), findsOneWidget);
    await tester.tap(find.text('Unificada'));
    await tester.pumpAndSettle();
    expect(find.text('Dividida'), findsOneWidget);

    expect(find.text('Completo'), findsOneWidget);
    await tester.tap(find.text('Completo'));
    await tester.pumpAndSettle();
    expect(find.text('Solo diffs'), findsOneWidget);
  });

  testWidgets('indica cuando no hay diferencias', (tester) async {
    await _openDiff(tester, original: base, modified: base);

    expect(find.text('sin cambios'), findsOneWidget);
    expect(find.text('✓ Sin cambios'), findsOneWidget);
  });

  testWidgets('persiste la vista elegida en SharedPreferences', (tester) async {
    const modified = 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;';

    await _openDiff(tester, original: base, modified: modified);

    // Cambia a vista dividida + solo diffs
    await tester.tap(find.text('Unificada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completo'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('diff_side_by_side'), isTrue);
    expect(prefs.getBool('diff_show_all_lines'), isFalse);
  });

  testWidgets('restaura la vista guardada al reabrir el diff', (tester) async {
    SharedPreferences.setMockInitialValues({
      'diff_side_by_side': true,
      'diff_show_all_lines': false,
    });

    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.text('Dividida'), findsOneWidget);
    expect(find.text('Solo diffs'), findsOneWidget);
  });

  testWidgets('se muestra como modal contenido, no a pantalla completa',
      (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
      windowSize: const Size(1600, 1000),
    );

    // El modal mide ~90% de la ventana, no la ocupa entera.
    final modal = tester.getSize(find.byType(NativeDiffViewer));
    expect(modal.width, lessThan(1600));

    // Maximizar lo lleva a ocupar toda la ventana.
    await tester.tap(find.byTooltip('Maximizar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NativeDiffViewer)).width, 1600);

    // Y se puede restaurar.
    expect(find.byTooltip('Restaurar tamaño'), findsOneWidget);
  });

  testWidgets('colapsa las etiquetas de la toolbar en ventanas angostas',
      (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
      windowSize: const Size(700, 600),
    );

    // Sin overflow y sin etiquetas: sólo iconos con tooltip.
    expect(tester.takeException(), isNull);
    expect(find.text('Completo'), findsNothing);
    expect(find.text('Unificada'), findsNothing);
    expect(find.byTooltip('Vista lado a lado'), findsOneWidget);
  });

  testWidgets('se cierra al tocar fuera del modal', (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
