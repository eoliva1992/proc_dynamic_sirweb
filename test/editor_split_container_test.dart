import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/editor_split_container.dart';

void main() {
  group('EditorSplitContainer', () {
    testWidgets('renderiza solo primaryChild cuando splitMode es none', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorSplitContainer(
              splitMode: EditorSplitMode.none,
              primaryChild: const Text('Primary Editor'),
              secondaryChild: const Text('Secondary Editor'),
            ),
          ),
        ),
      );

      expect(find.text('Primary Editor'), findsOneWidget);
      expect(find.text('Secondary Editor'), findsNothing);
    });

    testWidgets('renderiza ambos hijos cuando splitMode es vertical', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorSplitContainer(
              splitMode: EditorSplitMode.vertical,
              primaryChild: const Text('Primary Editor'),
              secondaryChild: const Text('Secondary Editor'),
            ),
          ),
        ),
      );

      expect(find.text('Primary Editor'), findsOneWidget);
      expect(find.text('Secondary Editor'), findsOneWidget);
    });

    testWidgets('renderiza ambos hijos cuando splitMode es horizontal', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorSplitContainer(
              splitMode: EditorSplitMode.horizontal,
              primaryChild: const Text('Primary Editor'),
              secondaryChild: const Text('Secondary Editor'),
            ),
          ),
        ),
      );

      expect(find.text('Primary Editor'), findsOneWidget);
      expect(find.text('Secondary Editor'), findsOneWidget);
    });

    testWidgets('invoca onCloseSecondary al hacer tap en botón de cerrar', (
      tester,
    ) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorSplitContainer(
              splitMode: EditorSplitMode.vertical,
              primaryChild: const Text('Primary Editor'),
              secondaryChild: const Text('Secondary Editor'),
              onCloseSecondary: () => closed = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(closed, isTrue);
    });
  });
}
