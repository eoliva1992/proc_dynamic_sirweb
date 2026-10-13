import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_state_controller.dart';
import 'package:proc_dynamic_sirweb/widgets/sql_executor/sql_executor_status_bar.dart';
import 'package:proc_dynamic_sirweb/widgets/sql_executor/sql_executor_toolbar.dart';

void main() {
  testWidgets(
    'SqlExecutorToolbar renderiza botones para nuevo, abrir, guardar y revelar archivo local',
    (tester) async {
      var newCalled = false;
      var openCalled = false;
      var saveCalled = false;
      var saveAsCalled = false;
      var revealCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlExecutorToolbar(
              ambiente: 'Desa',
              onAmbienteChanged: (_) {},
              statement: const SqlStatement(
                text: 'SELECT 1 FROM DUAL;',
                startLine: 1,
                endLine: 1,
                startOffset: 0,
                endOffset: 19,
                kind: SqlStatementKind.select,
              ),
              running: false,
              onExecuteCurrent: () {},
              onExecuteAll: () {},
              onExplainPlan: () {},
              onClearOutput: () {},
              onNewFile: () => newCalled = true,
              onOpenFile: () => openCalled = true,
              onSaveFile: () => saveCalled = true,
              onSaveFileAs: () => saveAsCalled = true,
              onRevealInExplorer: () => revealCalled = true,
              currentFilePath: 'C:\\test\\query.sql',
            ),
          ),
        ),
      );

      expect(find.byTooltip('Nuevo script limpio (Ctrl+N)'), findsOneWidget);
      expect(
        find.byTooltip('Abrir archivo local (.sql / .txt)'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Guardar en disco (Ctrl+S) — query.sql'),
        findsOneWidget,
      );
      expect(find.byTooltip('Guardar como… (Ctrl+Shift+S)'), findsOneWidget);
      expect(
        find.byTooltip('Abrir ubicación en el explorador\nC:\\test\\query.sql'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Nuevo script limpio (Ctrl+N)'));
      expect(newCalled, isTrue);

      await tester.tap(find.byTooltip('Abrir archivo local (.sql / .txt)'));
      expect(openCalled, isTrue);

      await tester.tap(find.byTooltip('Guardar en disco (Ctrl+S) — query.sql'));
      expect(saveCalled, isTrue);

      await tester.tap(find.byTooltip('Guardar como… (Ctrl+Shift+S)'));
      expect(saveAsCalled, isTrue);

      await tester.tap(
        find.byTooltip('Abrir ubicación en el explorador\nC:\\test\\query.sql'),
      );
      expect(revealCalled, isTrue);
    },
  );

  testWidgets(
    'SqlExecutorToolbar oculta botón de revelar cuando no hay ruta asignada',
    (tester) async {
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
              currentFilePath: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.folder_shared_outlined), findsNothing);
    },
  );

  testWidgets(
    'SqlExecutorStatusBar muestra la ruta del archivo local y permite tooltip',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SqlExecutorStatusBar(
              cursorLine: 1,
              cursorCol: 1,
              statementCount: 1,
              statement: null,
              running: false,
              lastEntry: null,
              ambiente: 'Desa',
              currentFilePath: 'C:\\scripts\\report.sql',
            ),
          ),
        ),
      );

      expect(find.text('C:\\scripts\\report.sql'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'SqlExecutorStatusBar muestra texto para script nuevo cuando no hay ruta',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SqlExecutorStatusBar(
              cursorLine: 1,
              cursorCol: 1,
              statementCount: 0,
              statement: null,
              running: false,
              lastEntry: null,
              ambiente: 'Desa',
              currentFilePath: null,
            ),
          ),
        ),
      );

      expect(find.text('Script nuevo (sin guardar)'), findsOneWidget);
      expect(find.byIcon(Icons.edit_document), findsOneWidget);
    },
  );

  test(
    'SqlExecutorStateController gestiona currentFilePath y loadFromLocalFile',
    () {
      final controller = SqlExecutorStateController(
        initialAmbiente: 'Desa',
        initialSql: 'SELECT 1;',
      );

      expect(controller.currentFilePath, isNull);

      controller.setCurrentFilePath('C:\\queries\\test.sql');
      expect(controller.currentFilePath, equals('C:\\queries\\test.sql'));

      controller.loadFromLocalFile(
        path: 'C:\\queries\\updated.sql',
        content: 'SELECT * FROM CLIENTE;',
      );
      expect(controller.currentFilePath, equals('C:\\queries\\updated.sql'));
      expect(controller.text, equals('SELECT * FROM CLIENTE;'));

      controller.dispose();
    },
  );
}
