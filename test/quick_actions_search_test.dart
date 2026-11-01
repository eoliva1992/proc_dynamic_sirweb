import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/procedure_list.dart';
import 'package:proc_dynamic_sirweb/widgets/search_tab_state.dart';

void main() {
  testWidgets(
    'ProcedureList shows quick action buttons when empty and invokes callbacks',
    (tester) async {
      final state = SearchTabState();

      bool blankClicked = false;
      bool sqlClicked = false;
      bool transferClicked = false;
      bool ticketsClicked = false;
      bool noteClicked = false;
      bool compareClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcedureList(
              tabState: state,
              onOpenBlank: () => blankClicked = true,
              onOpenSqlExecutor: () => sqlClicked = true,
              onBatchTransfer: () => transferClicked = true,
              onDeployTickets: () => ticketsClicked = true,
              onNewNote: () => noteClicked = true,
              onCompare: () => compareClicked = true,
            ),
          ),
        ),
      );

      // Initial pump and settle
      await tester.pumpAndSettle();

      // Verify presence of section title and action buttons
      expect(find.text('Acceso rápido'), findsOneWidget);
      expect(find.text('Doc. en blanco'), findsOneWidget);
      expect(find.text('Editor de SQL'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);
      expect(find.text('Ticket despliegue'), findsOneWidget);
      expect(find.text('Nueva nota'), findsOneWidget);
      expect(find.text('Comparar'), findsOneWidget);

      // Tap each action button
      await tester.tap(find.text('Doc. en blanco'));
      await tester.pump();
      expect(blankClicked, isTrue);

      await tester.tap(find.text('Editor de SQL'));
      await tester.pump();
      expect(sqlClicked, isTrue);

      await tester.tap(find.text('Transferencia'));
      await tester.pump();
      expect(transferClicked, isTrue);

      await tester.tap(find.text('Ticket despliegue'));
      await tester.pump();
      expect(ticketsClicked, isTrue);

      await tester.tap(find.text('Nueva nota'));
      await tester.pump();
      expect(noteClicked, isTrue);

      await tester.tap(find.text('Comparar'));
      await tester.pump();
      expect(compareClicked, isTrue);
    },
  );
}
