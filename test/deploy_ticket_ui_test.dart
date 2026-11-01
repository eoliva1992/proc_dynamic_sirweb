import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/services/connection_status_service.dart';
import 'package:proc_dynamic_sirweb/services/deploy_ticket_service.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/deploy_tickets_browser_dialog.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/deploy_ticket_editor_dialog.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/reverse_sql_config_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeployTicketService.setHttpClientForTesting(null);
  });

  tearDown(() {
    DeployTicketService.setHttpClientForTesting(null);
    ConnectionStatusService.instance.stopHeartbeatForTesting();
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

  testWidgets(
    'DeployTicketEditorDialog muestra sugerencias de Tipo de Solicitud (TPSOL) al interactuar',
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
          home: Scaffold(body: DeployTicketEditorDialog(onClose: () {})),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final tipoSolField = find.widgetWithText(
        TextFormField,
        'Tipo de Solicitud (TPSOL) *',
      );
      expect(tipoSolField, findsOneWidget);

      // Limpiar o escribir texto para disparar sugerencias
      await tester.enterText(tipoSolField, 'Mat');
      await tester.pumpAndSettle();

      // Debe aparecer la sugerencia "Matriz"
      expect(find.text('Matriz'), findsOneWidget);

      // Al tocar la sugerencia "Matriz", debe seleccionarse
      await tester.tap(find.text('Matriz'));
      await tester.pumpAndSettle();

      // El campo debe contener 'Matriz'
      final textFormFieldWidget = tester.widget<TextFormField>(tipoSolField);
      expect(textFormFieldWidget.controller?.text, 'Matriz');
    },
  );

  testWidgets(
    'DeployTicketsBrowserDialog inicializa el filtro Creado por con cdUsuario del provider',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      procedimientosProvider.setCdUsuario('USR_TEST');

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(body: DeployTicketsBrowserDialog(onClose: () {})),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final userCreaField = find.widgetWithText(
        TextField,
        'Creado por (USR)...',
      );
      expect(userCreaField, findsOneWidget);

      final textFieldWidget = tester.widget<TextField>(userCreaField);
      expect(textFieldWidget.controller?.text, 'USR_TEST');
    },
  );

  testWidgets(
    'Guardar configuración YAML abierta desde Artefactos en consulta de tickets guarda en el ticket',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Map<String, dynamic>? putPayload;

      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [
                  {
                    'id': 'ticket-rsql-1',
                    'version': 1,
                    'autoriza': 'ARTORRES',
                    'tipoSolicitud': 'Freshserver',
                    'numeroSolicitud': 'INC-99999',
                    'usuarioCrea': 'EOLIVA',
                    'reverseSql': [
                      {
                        'nombre': 'configReverse01112026',
                        'contenido': '''
dbconfig:
  tables:
    - dml: MERGE
      name: PRODUCTO
      filters:
        CD_PRODUCTO: "= 10"
''',
                      },
                    ],
                  },
                ],
                'pagina': 1,
                'top': 25,
                'tieneSiguiente': false,
                'tienePrevio': false,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.method == 'PUT' &&
            request.url.path.endsWith('/ticket-rsql-1')) {
          putPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'ticket-rsql-1',
                'version': 1,
                'autoriza': 'ARTORRES',
                'tipoSolicitud': 'Freshserver',
                'numeroSolicitud': 'INC-99999',
                'usuarioCrea': 'EOLIVA',
                'usuarioActualiza': putPayload!['usuarioActualiza'],
                'reverseSql': putPayload!['reverseSql'],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      DeployTicketService.setHttpClientForTesting(mockClient);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(body: DeployTicketsBrowserDialog(onClose: () {})),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ir a la pestaña "Artefactos" del inspector
      final artifactsTab = find.text('Artefactos (1)');
      expect(artifactsTab, findsOneWidget);
      await tester.tap(artifactsTab);
      await tester.pumpAndSettle();

      // Hacer clic sobre el artefacto RSQL
      final rsqlChip = find.text('configReverse01112026');
      expect(rsqlChip, findsOneWidget);
      await tester.tap(rsqlChip);
      await tester.pumpAndSettle();

      // Verificar que se abrió ReverseSqlConfigDialog
      expect(find.byType(ReverseSqlConfigDialog), findsOneWidget);

      // Expandir y modificar filtro
      await tester.tap(find.text('Expandir todo'));
      await tester.pump();

      final filterField = find.widgetWithText(TextField, '= 10');
      expect(filterField, findsOneWidget);
      await tester.enterText(filterField, '= 777');
      await tester.pump();

      // Pulsar "Aplicar a Ticket"
      await tester.tap(find.text('Aplicar a Ticket'));
      await tester.pumpAndSettle();

      // Debe haberse enviado el PUT al servidor con el YAML actualizado
      expect(putPayload, isNotNull);
      final updatedRsql = putPayload!['reverseSql'] as List<dynamic>;
      expect(updatedRsql, hasLength(1));
      expect(updatedRsql.first['nombre'], 'configReverse01112026');
      expect(updatedRsql.first['contenido'], contains('= 777'));

      // El diálogo se cerró y al reabrir el artefacto debe tener el nuevo contenido
      expect(find.byType(ReverseSqlConfigDialog), findsNothing);
      await tester.tap(find.text('configReverse01112026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expandir todo'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '= 777'), findsOneWidget);

      ConnectionStatusService.instance.stopHeartbeatForTesting();
    },
  );
}
