import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/screens/transfer_diff_page.dart';
import 'package:proc_dynamic_sirweb/widgets/native_diff_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openTransferDiff(
  WidgetTester tester, {
  required Procedimiento proc,
  required String sourceCode,
  required String sourceAmbiente,
  required String targetAmbiente,
  Size windowSize = const Size(1400, 900),
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: rootNavigatorKey,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTransferDiff(
                context,
                sourceProc: proc,
                sourceCode: sourceCode,
                sourceAmbiente: sourceAmbiente,
                targetAmbiente: targetAmbiente,
                cdUsuario: 'TESTUSER',
              ),
              child: const Text('abrir_transfer'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir_transfer'));
  await tester.pump();
}

void main() {
  final testProc = Procedimiento(
    cdProcedimiento: 'PR_TRANSFER_TEST',
    deTexto: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    inConfiguracion: 'D',
    version: 1,
    stProcedimiento: '1',
  );

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'showTransferDiff abre ventana flotante con toolbar y controles unificados',
    (tester) async {
      await _openTransferDiff(
        tester,
        proc: testProc,
        sourceCode: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
        sourceAmbiente: 'Desa',
        targetAmbiente: 'QA',
      );

      // Debe mostrar la etiqueta TRANSFERENCIA y los badges de origen y destino
      expect(find.text('TRANSFERENCIA'), findsOneWidget);
      expect(find.text('PR_TRANSFER_TEST'), findsOneWidget);
      expect(find.text('ORIGEN: Desa'), findsOneWidget);
      expect(find.text('DESTINO: QA'), findsOneWidget);

      // Debe mostrar los badges de los roles en la toolbar
      expect(find.text('ORIGEN'), findsWidgets);
      expect(find.text('DESTINO'), findsWidgets);

      // Debe contar con las acciones de transferencia
      expect(find.text('Backup destino'), findsOneWidget);
      expect(find.text('Guardar en Desa'), findsOneWidget);
      expect(find.text('Guardar en QA'), findsOneWidget);
      expect(find.text('Transferir a QA'), findsOneWidget);

      // Debe tener el visor de diff nativo unificado una vez cargado
      await tester.pumpAndSettle();
      expect(find.byType(NativeDiffViewer), findsOneWidget);
    },
  );
}
