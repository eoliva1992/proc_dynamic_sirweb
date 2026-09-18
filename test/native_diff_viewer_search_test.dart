import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/native_diff_viewer.dart';

void main() {
  testWidgets('edita una línea directamente dentro del visor', (tester) async {
    bool? editedSource;
    String? editedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeDiffViewer(
            origText: 'BEGIN\n  NULL;\nEND;',
            modText: 'BEGIN\n  NULL;\nEND;',
            sideBySide: true,
            showAllLines: true,
            editableSide: DiffEditSide.source,
            onEditLine: (isSource, _, value) {
              editedSource = isSource;
              editedValue = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = find.byType(TextFormField).first;
    await tester.enterText(editor, 'DECLARE');
    await tester.testTextInput.receiveAction(TextInputAction.done);

    expect(editedSource, isTrue);
    expect(editedValue, 'DECLARE');
  });

  testWidgets('resalta coincidencias sin quitar filas del diff', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativeDiffViewer(
            origText: 'BEGIN\n  -- buscar esto\nEND;',
            modText: 'BEGIN\n  -- buscar esto tambien\nEND;',
            sideBySide: false,
            showAllLines: true,
            searchQuery: 'buscar',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('buscar'), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                const Color(0xFFFFF3B0),
      ),
      findsNWidgets(2),
    );
  });
}
