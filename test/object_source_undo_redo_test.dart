import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/object_source_page.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'muestra botones de deshacer y rehacer en la toolbar de ObjectSourcePage',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: ObjectSourcePage(
            name: 'PR_TEST_UNDO',
            objectType: 'PROCEDURE',
            ambiente: 'Desa',
            initialData: (
              spec:
                  'CREATE OR REPLACE PROCEDURE PR_TEST_UNDO AS BEGIN NULL; END;',
              body: null,
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.byType(ObjectSourcePage), findsOneWidget);
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
      expect(find.byIcon(Icons.redo_rounded), findsOneWidget);

      final undoButton = find.ancestor(
        of: find.byIcon(Icons.undo_rounded),
        matching: find.byType(IconButton),
      );
      final redoButton = find.ancestor(
        of: find.byIcon(Icons.redo_rounded),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
      expect(tester.widget<IconButton>(redoButton).onPressed, isNull);

      final undoTooltip = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Deshacer (Ctrl+Z)',
      );
      final redoTooltip = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Rehacer (Ctrl+Y)',
      );

      expect(undoTooltip, findsOneWidget);
      expect(redoTooltip, findsOneWidget);
    },
  );
}
