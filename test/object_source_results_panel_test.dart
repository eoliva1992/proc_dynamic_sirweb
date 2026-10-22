import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/object_compilation_entry.dart';
import 'package:proc_dynamic_sirweb/models/sql_http_trace.dart';
import 'package:proc_dynamic_sirweb/widgets/_editor_plsql_checker.dart';
import 'package:proc_dynamic_sirweb/widgets/object_source_results_panel.dart';

void main() {
  testWidgets(
    'ObjectSourceResultsPanel renderiza pestañas de Mensajes y Servidor',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tabController = TabController(length: 2, vsync: const TestVSync());

      final issues = [
        PlSqlIssue(
          line: 12,
          col: 5,
          endCol: 15,
          message: 'PLS-00201: identifier must be declared',
          severity: fm.MarkerSeverity.error,
          source: 'Oracle',
        ),
        PlSqlIssue(
          line: 25,
          col: 1,
          endCol: 10,
          message: 'PLW-05004: identifier is deprecated',
          severity: fm.MarkerSeverity.warning,
          source: 'PL/SQL',
        ),
      ];

      final traces = [
        SqlHttpTraceEntry(
          id: 1,
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'http://localhost:5000/mcp/compile_object_ddl',
          endpoint: '/mcp/compile_object_ddl',
          requestBody: '{"name":"SP_TEST"}',
          responseBody: '{"success":true}',
          statusCode: 200,
          durationMs: 45,
          status: SqlHttpTraceStatus.success,
        ),
      ];

      double currentHeight = 220;
      bool visible = true;
      bool isPinned = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectSourceResultsPanel(
              tabController: tabController,
              visible: visible,
              height: currentHeight,
              onHeightChanged: (newH) => currentHeight = newH,
              onToggleVisible: () => visible = !visible,
              isPinned: isPinned,
              onTogglePinned: () => isPinned = !isPinned,
              issues: issues,
              checking: false,
              onJumpTo: (_) {},
              httpTraces: traces,
              lastCompilation: ObjectCompilationEntry(
                id: 1,
                timestamp: DateTime(2026, 10, 20, 10, 30),
                objectName: 'PKG_TEST',
                objectType: 'PACKAGE',
                part: 'BODY',
                ambiente: 'Desa',
                status: ObjectCompilationStatus.error,
                durationMs: 120,
                errorCount: 1,
                warningCount: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Salida'), findsOneWidget);
      expect(find.text('Mensajes'), findsOneWidget);
      expect(find.text('Servidor'), findsOneWidget);

      // Botón de pin
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

      // Banner de compilación en el tab de Mensajes
      expect(find.text('Compilación con errores'), findsOneWidget);
      expect(find.text('PACKAGE PKG_TEST (BODY)'), findsOneWidget);

      // Badges en las pestañas
      expect(find.text('2'), findsOneWidget); // 2 issues
      expect(find.text('1'), findsOneWidget); // 1 trace

      // Verifica que se muestre el issue en la pestaña Mensajes
      expect(find.textContaining('PLS-00201'), findsOneWidget);

      // Cambiar a la pestaña de Servidor (Trazas HTTP)
      await tester.tap(find.text('Servidor'));
      await tester.pumpAndSettle();

      expect(find.textContaining('/mcp/compile_object_ddl'), findsOneWidget);
      expect(find.textContaining('200 OK'), findsOneWidget);
    },
  );

  testWidgets(
    'ObjectSourceResultsPanel muestra compilación exitosa sin errores',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tabController = TabController(length: 2, vsync: const TestVSync());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectSourceResultsPanel(
              tabController: tabController,
              visible: true,
              height: 220,
              onHeightChanged: (_) {},
              onToggleVisible: () {},
              isPinned: false,
              onTogglePinned: () {},
              issues: const [],
              checking: false,
              onJumpTo: (_) {},
              lastCompilation: ObjectCompilationEntry(
                id: 2,
                timestamp: DateTime(2026, 10, 20, 10, 35),
                objectName: 'SP_CLIENTES',
                objectType: 'PROCEDURE',
                ambiente: 'QA',
                status: ObjectCompilationStatus.success,
                durationMs: 85,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Botón de pin sin fijar
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

      // Banner y estado exitoso
      expect(find.text('Compilado exitosamente'), findsOneWidget);
      expect(find.text('Compilación completada sin errores'), findsOneWidget);
      expect(
        find.text('PROCEDURE SP_CLIENTES en ambiente QA (85 ms)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ObjectSourceResultsPanel muestra errores de compilación transportados en la respuesta',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tabController = TabController(length: 2, vsync: const TestVSync());

      final issues = [
        PlSqlIssue(
          line: 1656,
          col: 44,
          endCol: 45,
          message: "PLS-00201: el identificador 'P_FE_CORTE' se debe declarar",
          severity: fm.MarkerSeverity.error,
          source: 'Oracle',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectSourceResultsPanel(
              tabController: tabController,
              visible: true,
              height: 250,
              onHeightChanged: (_) {},
              onToggleVisible: () {},
              issues: issues,
              checking: false,
              onJumpTo: (_) {},
              lastCompilation: ObjectCompilationEntry(
                id: 3,
                timestamp: DateTime(2026, 10, 20, 17, 49),
                objectName: 'PCK_API_RDO_PRODUCTO',
                objectType: 'PACKAGE BODY',
                ambiente: 'Desa',
                status: ObjectCompilationStatus.error,
                durationMs: 340,
                errorCount: 2,
                message: "'PCK_API_RDO_PRODUCTO' compilado con 2 error(es).",
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner superior con error
      expect(find.text('Compilación con errores'), findsOneWidget);
      expect(find.text('PACKAGE BODY PCK_API_RDO_PRODUCTO'), findsOneWidget);

      // Fila del error específico transportado en la respuesta
      expect(
        find.textContaining(
          "PLS-00201: el identificador 'P_FE_CORTE' se debe declarar",
        ),
        findsOneWidget,
      );
      expect(find.text('L1656:44'), findsOneWidget);
    },
  );

  testWidgets('ObjectSourceCollapsedHandle se renderiza y responde a onExpand', (
    tester,
  ) async {
    bool expanded = false;
    final issues = [
      PlSqlIssue(
        line: 10,
        col: 1,
        endCol: 10,
        message: 'PLS-00103',
        severity: fm.MarkerSeverity.error,
        source: 'Oracle',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ObjectSourceCollapsedHandle(
                onExpand: () => expanded = true,
                issues: issues,
                lastCompilation: ObjectCompilationEntry(
                  id: 4,
                  timestamp: DateTime.now(),
                  objectName: 'SP_DEMO',
                  objectType: 'PROCEDURE',
                  ambiente: 'Desa',
                  status: ObjectCompilationStatus.error,
                  durationMs: 50,
                  errorCount: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mostrar salida'), findsOneWidget);
    expect(find.text('1 error'), findsOneWidget);

    await tester.tap(find.text('Mostrar salida'));
    expect(expanded, isTrue);
  });

  testWidgets(
    'ProblemsOutputConsole invoca onClear tras confirmar diálogo',
    (tester) async {
      bool cleared = false;
      final issues = [
        PlSqlIssue(
          line: 10,
          col: 1,
          endCol: 10,
          message: 'Error sintaxis',
          severity: fm.MarkerSeverity.error,
          source: 'Oracle',
        ),
      ];

      final tabController = TabController(length: 2, vsync: const TestVSync());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectSourceResultsPanel(
              tabController: tabController,
              visible: true,
              height: 250,
              onHeightChanged: (_) {},
              onToggleVisible: () {},
              issues: issues,
              checking: false,
              onJumpTo: (_) {},
              onClearIssues: () => cleared = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final clearBtn = find.byTooltip('Limpiar mensajes');
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.text('Limpiar mensajes'), findsWidgets);
      expect(find.text('Cancelar'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Limpiar'));
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
    },
  );
}
