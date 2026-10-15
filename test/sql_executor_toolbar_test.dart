import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/widgets/sql_executor/sql_executor_toolbar.dart';

void main() {
  testWidgets(
    'HeroExecuteBtn en estado running muestra opción de Detener e invoca onCancel',
    (tester) async {
      var cancelInvoked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlExecutorToolbar(
              ambiente: 'Desa',
              onAmbienteChanged: (_) {},
              statement: const SqlStatement(
                text: 'SELECT 1 FROM dual;',
                kind: SqlStatementKind.select,
                startOffset: 0,
                endOffset: 19,
                startLine: 1,
                endLine: 1,
              ),
              running: true,
              onExecuteCurrent: () {},
              onExecuteAll: () {},
              onExplainPlan: () {},
              onCancel: () {
                cancelInvoked = true;
              },
              onClearOutput: () {},
            ),
          ),
        ),
      );

      // Debe mostrar tooltip de detención y el texto de Detener
      expect(find.byTooltip('Detener ejecución (Escape)'), findsOneWidget);
      expect(find.textContaining('Detener'), findsOneWidget);

      // Hacemos tap en el botón de ejecución para cancelar
      await tester.tap(find.byTooltip('Detener ejecución (Escape)'));
      await tester.pump();

      expect(cancelInvoked, isTrue);
    },
  );

  testWidgets(
    'SqlExecutorToolbar muestra selector de timeout y permite cambiar el valor',
    (tester) async {
      int? selectedTimeout;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlExecutorToolbar(
              ambiente: 'Desa',
              onAmbienteChanged: (_) {},
              statement: null,
              running: false,
              onExecuteCurrent: () {},
              onExecuteAll: () {},
              onExplainPlan: () {},
              onClearOutput: () {},
              timeoutSeconds: 60,
              onTimeoutChanged: (v) {
                selectedTimeout = v;
              },
            ),
          ),
        ),
      );

      // Verificamos que se muestra el timeout actual de 60s (1m)
      expect(find.text('1m'), findsOneWidget);

      // Abrimos el menú desplegable de timeout
      await tester.tap(find.text('1m'));
      await tester.pumpAndSettle();

      // Debe aparecer la opción de 2m (120s), 30m, 1h, 2h
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);

      // Seleccionamos 1h (3600s)
      await tester.tap(find.text('1h'));
      await tester.pumpAndSettle();

      expect(selectedTimeout, equals(3600));
    },
  );

  testWidgets(
    'SqlExecutorToolbar muestra controles de límite y Sin límite antes de ejecutar sentencia',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int? changedMaxRows;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlExecutorToolbar(
              ambiente: 'Desa',
              onAmbienteChanged: (_) {},
              statement: null,
              running: false,
              onExecuteCurrent: () {},
              onExecuteAll: () {},
              onExplainPlan: () {},
              onClearOutput: () {},
              maxRows: 100,
              onMaxRowsChanged: (val) => changedMaxRows = val,
            ),
          ),
        ),
      );

      // Los controles están visibles aun sin sentencia ni resultados previos
      expect(find.text('Límite'), findsOneWidget);
      expect(find.text('Sin límite'), findsOneWidget);
      expect(find.byIcon(Icons.all_inclusive_rounded), findsOneWidget);

      final textField = tester.widget<TextField>(
        find.widgetWithText(TextField, '100'),
      );
      expect(textField.enabled, isTrue);

      // Pulsamos "Sin límite"
      await tester.tap(find.text('Sin límite'));
      await tester.pumpAndSettle();

      expect(changedMaxRows, -1);

      // Re-renderizamos con maxRows = -1
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlExecutorToolbar(
              ambiente: 'Desa',
              onAmbienteChanged: (_) {},
              statement: null,
              running: false,
              onExecuteCurrent: () {},
              onExecuteAll: () {},
              onExplainPlan: () {},
              onClearOutput: () {},
              maxRows: -1,
              onMaxRowsChanged: (val) => changedMaxRows = val,
            ),
          ),
        ),
      );

      // Ahora el TextField debe estar deshabilitado
      final disabledTextField = tester.widget<TextField>(
        find.widgetWithText(TextField, '100'),
      );
      expect(disabledTextField.enabled, isFalse);

      // Pulsamos nuevamente el botón "Sin límite" para reactivarlo
      await tester.tap(find.text('Sin límite'));
      await tester.pumpAndSettle();

      // Debe restaurar el último valor finito (100)
      expect(changedMaxRows, 100);
    },
  );
}
