import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/widgets/sql_executor/sql_results_grid.dart';
import 'package:toastification/toastification.dart';

void main() {
  const sampleResult = SqlQueryResult(
    columns: [
      SqlColumn(name: 'ID', dataType: 'NUMBER'),
      SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
    ],
    rows: [
      [101, 'Alice'],
      [102, 'Bob'],
    ],
    returnedRows: 2,
    truncated: false,
    durationMs: 12,
  );

  testWidgets('SqlResultsGrid permite seleccionar celda o fila completa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SqlResultsGrid(result: sampleResult, maxRows: 100),
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    // Clic en la celda 'Alice' para seleccionarla
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    // Checkbox de fila 1 para seleccionar fila completa
    final checkboxes = find.byType(Checkbox);
    // El primero es el 'select all', el segundo es la fila 1
    expect(checkboxes, findsWidgets);
    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();

    // Debe indicar 1 seleccionada
    expect(find.text('1 seleccionada'), findsOneWidget);
  });

  testWidgets(
    'SqlResultsGrid permite selección múltiple de celdas con Ctrl y Shift',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SqlResultsGrid(result: sampleResult, maxRows: 100),
          ),
        ),
      );

      // Clic en 'Alice' (fila 0, col 1)
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // Clic con Ctrl en '101' (fila 0, col 0) para agregarla a la selección
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('101'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Deseleccionar con tecla Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Ctrl+Shift+C copia encabezado y celda seleccionada sin afectar Ctrl+C',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final clipboardTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map;
            clipboardTexts.add(args['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        const ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: SqlResultsGrid(result: sampleResult, maxRows: 100),
            ),
          ),
        ),
      );

      // Foco en la grilla: requerido para que los atajos de teclado se activen.
      await tester.tap(find.text('Alice'));
      // El GestureDetector de la celda tiene onDoubleTap, así que el tap
      // simple sólo se resuelve tras el timeout de doble-tap.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      tester
          .widget<Focus>(find.byKey(const Key('sqlResultsGridFocus')))
          .focusNode!
          .requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboardTexts, contains('NAME\nAlice'));

      // Ctrl+C sigue copiando la celda seleccionada, no los encabezados.
      clipboardTexts.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboardTexts, contains('Alice'));
    },
  );

  testWidgets(
    'Ctrl+Shift+C con fila completa seleccionada copia encabezado y fila',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final clipboardTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map;
            clipboardTexts.add(args['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        const ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: SqlResultsGrid(result: sampleResult, maxRows: 100),
            ),
          ),
        ),
      );

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();
      tester
          .widget<Focus>(find.byKey(const Key('sqlResultsGridFocus')))
          .focusNode!
          .requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboardTexts, contains('ID\tNAME\n101\tAlice'));
    },
  );
}
