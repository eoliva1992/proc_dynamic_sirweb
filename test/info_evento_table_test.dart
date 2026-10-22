import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/evento_info.dart';
import 'package:proc_dynamic_sirweb/widgets/code_editor_panel.dart';

void main() {
  testWidgets('InfoEventoVirtualTable renders 2000 rows virtualized efficiently', (
    tester,
  ) async {
    final vertCtrl = ScrollController();
    final horizCtrl = ScrollController();
    final selectedIndices = <int>{};

    final largeValores = List<EventoValor>.generate(2000, (i) {
      return EventoValor(
        indice: i + 1,
        valor: 'VAL_$i',
        descripcion: 'Descripcion $i',
        raw: {
          'CD_EVENTO': 'EVT_BENCHMARK',
          'VERSION': 1,
          'DE_INDICE_EVENTO': 'Indice $i',
          'VA_DATO1': 'Dato 1 - $i',
          'VA_DATO2': 'Dato 2 - $i',
          'VA_COMPONENTE': '$i.50',
          'FE_INICIO_REGISTRO': '2026-01-01',
          'FE_TERMINO_REGISTRO': '2026-12-31',
          'CD_USUARIO': 'TEST_USER',
        },
      );
    });

    final cols = [
      'VERSION',
      'CD_EVENTO',
      'DE_INDICE_EVENTO',
      'VA_DATO1',
      'VA_DATO2',
      'VA_COMPONENTE',
      'FE_INICIO_REGISTRO',
      'FE_TERMINO_REGISTRO',
      'CD_USUARIO',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: StatefulBuilder(
              builder: (context, setState) {
                return InfoEventoVirtualTable(
                  isDark: true,
                  borderColor: Colors.grey,
                  cols: cols,
                  valores: largeValores,
                  cdEvento: 'EVT_BENCHMARK',
                  vertCtrl: vertCtrl,
                  horizCtrl: horizCtrl,
                  selectedRowIndices: selectedIndices,
                  onToggleSelectAll: (val) {
                    setState(() {
                      if (val == true) {
                        selectedIndices.addAll(List.generate(2000, (i) => i));
                      } else {
                        selectedIndices.clear();
                      }
                    });
                  },
                  onToggleRow: (idx, val) {
                    setState(() {
                      if (val == true) {
                        selectedIndices.add(idx);
                      } else {
                        selectedIndices.remove(idx);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify header column labels are rendered
    expect(find.text('Versión'), findsOneWidget);
    expect(find.text('Evento'), findsOneWidget);
    expect(find.text('Descripción índice'), findsOneWidget);

    // Verify first row is visible
    expect(find.text('Indice 0'), findsOneWidget);

    // Verify un-rendered row 1500 is NOT instantiated in the tree (virtualized!)
    expect(find.text('Indice 1500'), findsNothing);

    // Scroll down to row 100
    vertCtrl.jumpTo(100 * 30.0);
    await tester.pump();

    // After scrolling, row 100 should be visible and row 0 should be recycled/culled
    expect(find.text('Indice 100'), findsOneWidget);
    expect(find.text('Indice 0'), findsNothing);
  });
}
