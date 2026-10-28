import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/artifact_list_editor.dart';

void main() {
  testWidgets('ArtifactListEditor agrega elemento con Enter', (tester) async {
    List<String> items = ['PROC_1'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ArtifactListEditor(
                title: 'Procedimientos',
                hintText: 'Ingresa procedimiento',
                icon: Icons.bolt,
                color: Colors.blue,
                items: items,
                onChanged: (updated) => setState(() => items = updated),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('PROC_1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Escribir un nuevo ítem
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'PROC_2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(items, contains('PROC_2'));
    expect(find.text('PROC_2'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('ArtifactListEditor parsea y separa texto con comas al pegar', (
    tester,
  ) async {
    List<String> items = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ArtifactListEditor(
                title: 'Reglas de Negocio',
                hintText: 'Ingresa regla',
                icon: Icons.rule,
                color: Colors.amber,
                items: items,
                onChanged: (updated) => setState(() => items = updated),
              );
            },
          ),
        ),
      ),
    );

    // Ingresar string con comas
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'RN_A, RN_B, RN_C, RN_A');
    await tester.pump();
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    // Comprobar que agregó los 3 elementos sin duplicados
    expect(items.length, 3);
    expect(items, ['RN_A', 'RN_B', 'RN_C']);
    expect(find.text('RN_A'), findsOneWidget);
    expect(find.text('RN_B'), findsOneWidget);
    expect(find.text('RN_C'), findsOneWidget);
  });

  testWidgets(
    'ArtifactListEditor elimina elementos con botón (x) y limpiar todo',
    (tester) async {
      List<String> items = ['ITEM_1', 'ITEM_2'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ArtifactListEditor(
                  title: 'Scripts SQL',
                  hintText: 'Ingresa script',
                  icon: Icons.code,
                  color: Colors.teal,
                  items: items,
                  onChanged: (updated) => setState(() => items = updated),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('ITEM_1'), findsOneWidget);
      expect(find.text('ITEM_2'), findsOneWidget);

      // Eliminar el primer chip haciendo clic en su botón de cerrar
      final closeIcons = find.byIcon(Icons.close_rounded);
      expect(closeIcons, findsNWidgets(2));
      await tester.tap(closeIcons.first);
      await tester.pumpAndSettle();

      expect(items, ['ITEM_2']);

      // Clic en Limpiar
      final clearBtn = find.text('Limpiar');
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(items, isEmpty);
      expect(find.text('Limpiar'), findsNothing);
    },
  );
}
