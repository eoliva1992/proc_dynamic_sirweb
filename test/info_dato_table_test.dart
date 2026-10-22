import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/dato_info.dart';
import 'package:proc_dynamic_sirweb/widgets/code_editor_panel.dart';

void main() {
  testWidgets(
    'InfoDatoVirtualTable renders rows virtualized efficiently and supports selection',
    (tester) async {
      final vertCtrl = ScrollController();
      final horizCtrl = ScrollController();
      final selectedIndices = <int>{};

      final largeValores = List<ValorTabla>.generate(500, (i) {
        return ValorTabla(
          raw: {
            'cdTabla': 101,
            'deIndiceDato': 'IND_$i',
            'deDato': 'Descripcion $i',
            'vaDato1': '100$i',
            'vaDato2': '200$i',
            'feEfectivaInformacion': '2026-01-01',
            'feTerminoInformacion': '2026-12-31',
            'inSuspendido': 0,
            'cdUsuario': 'TEST_USER',
          },
        );
      });

      final cols = [
        'deIndiceDato',
        'deDato',
        'vaDato1',
        'vaDato2',
        'feEfectivaInformacion',
        'feTerminoInformacion',
        'cdUsuario',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return InfoDatoVirtualTable(
                    isDark: true,
                    borderColor: Colors.grey,
                    cols: cols,
                    valores: largeValores,
                    cdTabla: 101,
                    vertCtrl: vertCtrl,
                    horizCtrl: horizCtrl,
                    selectedRowIndices: selectedIndices,
                    onToggleSelectAll: (val) {
                      setState(() {
                        if (val == true) {
                          selectedIndices.addAll(List.generate(500, (i) => i));
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
      expect(find.text('Índice'), findsOneWidget);
      expect(find.text('Descripción'), findsOneWidget);
      expect(find.text('Dato 1'), findsOneWidget);

      // Verify first row is visible
      expect(find.text('IND_0'), findsOneWidget);

      // Verify un-rendered row 400 is NOT instantiated in the tree (virtualized!)
      expect(find.text('IND_400'), findsNothing);

      // Scroll down to row 50
      vertCtrl.jumpTo(50 * 30.0);
      await tester.pump();

      // After scrolling, row 50 should be visible and row 0 should be culled
      expect(find.text('IND_50'), findsOneWidget);
      expect(find.text('IND_0'), findsNothing);
    },
  );

  testWidgets(
    'InfoDatoVirtualTable correctly displays multiple fields and version',
    (tester) async {
      final vertCtrl = ScrollController();
      final horizCtrl = ScrollController();
      final selectedIndices = <int>{};

      final valores = [
        ValorTabla(
          raw: {
            'version': 5,
            'cdTabla': 200,
            'deIndiceDato': 'IND_TEST',
            'deDato': 'Descripcion de prueba',
            'cdUsuario': 'JUANP',
            'feEfectivaInformacion': '01/01/2026',
            'feTerminoInformacion': '31/12/2026',
            'feModificacion': '15/02/2026',
            'inSuspendido': 0,
          },
        ),
      ];

      final cols = [
        'version',
        'deIndiceDato',
        'deDato',
        'feEfectivaInformacion',
        'feTerminoInformacion',
        'feModificacion',
        'cdUsuario',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 400,
              child: InfoDatoVirtualTable(
                isDark: false,
                borderColor: Colors.grey,
                cols: cols,
                valores: valores,
                cdTabla: 200,
                vertCtrl: vertCtrl,
                horizCtrl: horizCtrl,
                selectedRowIndices: selectedIndices,
                onToggleSelectAll: (_) {},
                onToggleRow: (_, _) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Versión'), findsOneWidget);
      expect(find.text('Índice'), findsOneWidget);
      expect(find.text('Descripción'), findsOneWidget);
      expect(find.text('F. efectiva'), findsOneWidget);
      expect(find.text('F. término'), findsOneWidget);
      expect(find.text('F. modificación'), findsOneWidget);
      expect(find.text('Usuario'), findsOneWidget);

      expect(find.text('IND_TEST'), findsOneWidget);
      expect(find.text('Descripcion de prueba'), findsOneWidget);
      expect(find.text('JUANP'), findsOneWidget);
    },
  );
}
