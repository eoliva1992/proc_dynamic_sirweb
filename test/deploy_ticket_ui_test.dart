import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/deploy_tickets_browser_dialog.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/deploy_ticket_editor_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'DeployTicketsBrowserDialog abre DeployTicketEditorDialog al presionar Nuevo Ticket',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(body: DeployTicketsBrowserDialog(onClose: () {})),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificar que existe el botón "Nuevo Ticket"
      final newBtn = find.text('Nuevo Ticket');
      expect(newBtn, findsOneWidget);

      // Hacer clic en "Nuevo Ticket"
      await tester.tap(newBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Debe renderizarse el editor de ticket
      expect(find.byType(DeployTicketEditorDialog), findsOneWidget);
      expect(find.text('Nuevo Ticket de Despliegue Git'), findsOneWidget);
    },
  );

  testWidgets(
    'showDeployTicketsBrowser abre el diálogo de mantenimiento desde contexto con overlay',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showDeployTicketsBrowser(ctx),
                  child: const Text('Abrir Mantenimiento'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Abrir Mantenimiento'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DeployTicketsBrowserDialog), findsOneWidget);
      expect(
        find.text('Mantenimiento de Tickets de Despliegue'),
        findsOneWidget,
      );
    },
  );
}
