import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/widgets/sql_executor/sql_explain_plan_view.dart';

void main() {
  testWidgets(
    'SqlExplainPlanView does not overflow at narrow widths (e.g. 320px)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final nodes = [
        const SqlExplainPlanNode(
          id: 0,
          operation: 'SELECT STATEMENT',
          options: null,
          depth: 0,
          cost: 154,
          cardinality: 1000,
          bytes: 409600,
        ),
        const SqlExplainPlanNode(
          id: 1,
          parentId: 0,
          operation: 'TABLE ACCESS',
          options: 'FULL',
          objectOwner: 'OWNER_PROD_VERY_LONG_NAME',
          objectName: 'VERY_LONG_TABLE_NAME_ACCESS_SAMPLE',
          objectType: 'TABLE',
          depth: 3,
          cost: 120,
          cardinality: 500,
          bytes: 204800,
          accessPredicate: 'COL_A = 123 AND COL_B = 456',
          filterPredicate: 'COL_C IS NOT NULL',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 500,
              child: SqlExplainPlanView(
                nodes: nodes,
                textPlan: const ['Plan hash value: 123456789'],
              ),
            ),
          ),
        ),
      );
      final exception = tester.takeException();
      if (exception is FlutterError) {
        debugPrint(exception.toStringDeep());
      }
      expect(exception, isNull);
      expect(find.text('Costo total: 154'), findsOneWidget);
      expect(find.text('TABLE ACCESS'), findsOneWidget);
    },
  );
  testWidgets(
    'SqlExplainPlanView does not overflow in wide and intermediate screens',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final nodes = [
        const SqlExplainPlanNode(
          id: 0,
          operation: 'SELECT STATEMENT',
          depth: 0,
          cost: 10,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 500,
              child: SqlExplainPlanView(
                nodes: nodes,
                textPlan: const ['Raw text line'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Jerarquía de operaciones Oracle'), findsOneWidget);
    },
  );
}
