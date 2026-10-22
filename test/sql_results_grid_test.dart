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

  testWidgets(
    'Navegación con flechas direccionales requiere clic previo en celda',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: SqlResultsGrid(result: sampleResult, maxRows: 100),
            ),
          ),
        ),
      );

      // Foco en el grid sin hacer clic previo en una celda
      tester
          .widget<Focus>(find.byKey(const Key('sqlResultsGridFocus')))
          .focusNode!
          .requestFocus();
      await tester.pump();

      // Pulsar flechas no debe seleccionar nada
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Intentar copiar con Ctrl+C no debe copiar celda individual
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

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Al no haber celdas seleccionadas, copia todo como CSV, no una celda individual
      expect(clipboardTexts, isNotEmpty);
      expect(clipboardTexts.first, contains('ID,NAME'));
    },
  );

  testWidgets(
    'Navegación con flechas mueve la celda seleccionada (simple y con Shift)',
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

      // Clic inicial en '101' (fila 0, col 0)
      await tester.tap(find.text('101'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      tester
          .widget<Focus>(find.byKey(const Key('sqlResultsGridFocus')))
          .focusNode!
          .requestFocus();
      await tester.pump();

      // Flecha derecha -> se mueve a 'Alice' (fila 0, col 1)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      clipboardTexts.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboardTexts.last, equals('Alice'));

      // Flecha abajo -> se mueve a 'Bob' (fila 1, col 1)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      clipboardTexts.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboardTexts.last, equals('Bob'));

      // Flecha izquierda -> se mueve a '102' (fila 1, col 0)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      clipboardTexts.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboardTexts.last, equals('102'));

      // Flecha arriba -> vuelve a '101' (fila 0, col 0)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      clipboardTexts.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboardTexts.last, equals('101'));

      // Selección en rango: Shift + Flecha Derecha, luego Shift + Flecha Abajo
      // Rango 2x2: (fila 0 col 0) a (fila 1 col 1) -> 101, Alice, 102, Bob
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      clipboardTexts.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboardTexts.last, equals('101\tAlice\n102\tBob'));
    },
  );

  testWidgets(
    'Filtro por columna filtra las filas mostradas y actualiza el contador',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: SqlResultsGrid(result: sampleResult, maxRows: 100),
            ),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('2 filas'), findsOneWidget);

      // Iconos de filtro por columna en los encabezados
      final filterIcons = find.byIcon(Icons.filter_alt_outlined);
      expect(filterIcons, findsWidgets);

      // Clic en el filtro de la segunda columna (NAME)
      await tester.tap(filterIcons.at(1));
      await tester.pumpAndSettle();

      // Debe abrir el popup anclado a la columna
      expect(find.text('Filtrar NAME'), findsOneWidget);

      // Ingresar 'ali' en el campo de texto del popup
      await tester.enterText(find.byType(TextField).last, 'ali');
      await tester.pumpAndSettle();

      // Pulsar botón 'Aplicar'
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      // Ahora solo debe estar Alice y no Bob
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('1 de 2 filas'), findsOneWidget);
      expect(find.text('1 filtro de col.'), findsOneWidget);

      // Limpiar filtro haciendo clic en la 'x' del chip en el toolbar
      await tester.tap(find.byTooltip('Limpiar todos los filtros de columnas'));
      await tester.pumpAndSettle();

      // Vuelven a mostrarse todas
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('2 filas'), findsOneWidget);
    },
  );

  testWidgets(
    'Selector de columnas permanece abierto al desmarcar y permite ocultar/mostrar varias columnas',
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

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Abrir el popover de columnas mediante su key
      final colBtn = find.byKey(const Key('sqlResultsGridColumnsBtn'));
      expect(colBtn, findsOneWidget);
      await tester.tap(colBtn);
      await tester.pumpAndSettle();

      // Debe verse el popover con encabezado "Columnas visibles" y las dos columnas
      expect(find.text('Columnas visibles'), findsOneWidget);
      expect(find.text('2 de 2'), findsOneWidget);
      expect(find.text('Filtrar columnas...'), findsOneWidget);

      // Desmarcar columna ID mediante su fila
      await tester.tap(find.text('ID').last);
      await tester.pumpAndSettle();

      // El popover permanece ABIERTO (no se cerró)
      expect(find.text('Columnas visibles'), findsOneWidget);
      expect(find.text('1 de 2'), findsOneWidget);

      // En el grid, la columna NAME sigue estando visible
      expect(find.text('Alice'), findsOneWidget);

      // Pulsar "Mostrar todas"
      expect(find.text('Mostrar todas'), findsOneWidget);
      await tester.tap(find.text('Mostrar todas'));
      await tester.pumpAndSettle();

      // Vuelve a marcar 2 de 2 y sigue abierto
      expect(find.text('2 de 2'), findsOneWidget);

      // Cerrar el popover pulsando la 'x'
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      // Ahora el popover está cerrado
      expect(find.text('Columnas visibles'), findsNothing);
    },
  );

  testWidgets(
    'Permite redimensionar columna arrastrando el divisor de la cabecera y reiniciar con doble tap',
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

      // Encontrar los mouse regions con cursor resizeColumn
      final resizeHandles = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(resizeHandles, findsNWidgets(2)); // Columna 0 (ID) y Columna 1 (NAME)

      // Arrastrar el handle de la primera columna hacia la derecha (+80 px)
      await tester.drag(resizeHandles.first, const Offset(80, 0));
      await tester.pumpAndSettle();

      // Doble tap en el handle para restablecer el tamaño
      await tester.tap(resizeHandles.first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(resizeHandles.first);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'SqlResultsGrid muestra badge de carga más y dispara callback al hacer clic',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      var loadMoreCalled = false;
      const truncatedResult = SqlQueryResult(
        columns: [
          SqlColumn(name: 'ID', dataType: 'NUMBER'),
          SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
        ],
        rows: [
          [101, 'Alice'],
          [102, 'Bob'],
        ],
        returnedRows: 2,
        truncated: true,
        durationMs: 12,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlResultsGrid(
              result: truncatedResult,
              maxRows: 2,
              onLoadMore: () {
                loadMoreCalled = true;
              },
            ),
          ),
        ),
      );

      // Debe aparecer el badge 'Truncado · +Cargar más'
      final badgeFinder = find.text('Truncado · +Cargar más');
      expect(badgeFinder, findsOneWidget);

      await tester.tap(badgeFinder);
      await tester.pumpAndSettle();

      expect(loadMoreCalled, isTrue);
    },
  );

  testWidgets(
    'SqlResultsGrid muestra indicador de cargando cuando isLoadingMore es true',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const truncatedResult = SqlQueryResult(
        columns: [
          SqlColumn(name: 'ID', dataType: 'NUMBER'),
          SqlColumn(name: 'NAME', dataType: 'VARCHAR2'),
        ],
        rows: [
          [101, 'Alice'],
          [102, 'Bob'],
        ],
        returnedRows: 2,
        truncated: true,
        durationMs: 12,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SqlResultsGrid(
              result: truncatedResult,
              maxRows: 2,
              isLoadingMore: true,
            ),
          ),
        ),
      );

      expect(find.text('Cargando...'), findsOneWidget);
      expect(find.text('Cargando siguientes filas...'), findsOneWidget);
    },
  );
}
