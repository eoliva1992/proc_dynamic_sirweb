import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/services/connection_status_service.dart';
import 'package:proc_dynamic_sirweb/services/deploy_ticket_service.dart';
import 'package:proc_dynamic_sirweb/services/note_service.dart';
import 'package:proc_dynamic_sirweb/widgets/constellation_background.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/link_existing_notes_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NoteService.setHttpClientForTesting(null);
    DeployTicketService.setHttpClientForTesting(null);
  });

  tearDown(() {
    NoteService.setHttpClientForTesting(null);
    DeployTicketService.setHttpClientForTesting(null);
    ConnectionStatusService.instance.stopHeartbeatForTesting();
  });

  final dummyNotes = [
    {
      'note': {
        'id': 'note-1',
        'title': 'Análisis de Incidencia de Pagos',
        'content': 'Detalle de la solución al problema de timeout en pagos.',
        'tags': ['fix', 'pagos'],
        'ownerUser': 'EOLIVA',
        'isActive': true,
        'version': 1,
        'createdAt': '2026-10-01T10:00:00.000Z',
        'ticketDespliegueId': null,
      },
      'accessLevel': 'owner',
    },
    {
      'note': {
        'id': 'note-2',
        'title': 'Script de rollback y contingencia',
        'content': 'Pasos manuales para restaurar tablas en caso de fallo.',
        'tags': ['rollback', 'dba'],
        'ownerUser': 'JPEREZ',
        'isActive': true,
        'version': 2,
        'createdAt': '2026-10-02T11:00:00.000Z',
        'ticketDespliegueId': '999',
      },
      'accessLevel': 'edit',
    },
    {
      'note': {
        'id': 'note-3',
        'title': 'Nota ya vinculada',
        'content': 'Esta nota ya está vinculada al ticket actual.',
        'tags': ['pase'],
        'ownerUser': 'EOLIVA',
        'isActive': true,
        'version': 1,
        'createdAt': '2026-10-03T12:00:00.000Z',
        'ticketDespliegueId': 'ticket-100',
      },
      'accessLevel': 'owner',
    },
  ];

  testWidgets(
    'LinkExistingNotesDialog renderiza cabecera ConstellationHeader, filtros y excluye notas ya vinculadas',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mock para NoteService
      NoteService.setHttpClientForTesting(
        MockClient((request) async {
          return http.Response(
            jsonEncode({'items': dummyNotes}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      List<String>? closedResult;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(
            body: LinkExistingNotesDialog(
              ticketId: 'ticket-100',
              ticketDisplayNumber: '54321',
              alreadyLinkedNoteIds: const ['note-3'], // Ya vinculada
              activeUser: 'EOLIVA',
              close: ([res]) => closedResult = res,
            ),
          ),
        ),
      );

      // Esperar carga asíncrona
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificar cabecera
      expect(find.byType(ConstellationHeader), findsOneWidget);
      expect(find.text('Vincular Nota de Trabajo'), findsOneWidget);
      expect(find.text('Ticket Solicitud #54321'), findsOneWidget);
      expect(
        find.text('2 disp.'),
        findsOneWidget,
      ); // note-1 y note-2 (note-3 excluida)

      // Verificar existencia de notas filtradas
      expect(find.text('Análisis de Incidencia de Pagos'), findsOneWidget);
      expect(find.text('Script de rollback y contingencia'), findsOneWidget);
      expect(find.text('Nota ya vinculada'), findsNothing);

      // Verificar aviso de reasignación en note-2
      expect(find.text('Reasignará de Pase #999'), findsOneWidget);

      // Cerrar modal
      final closeBtn = find.text('Cerrar');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      expect(closedResult, isEmpty);
    },
  );

  testWidgets(
    'Filtros por ámbito (Mis Notas / Compartidas) y buscador funcionan adecuadamente',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      NoteService.setHttpClientForTesting(
        MockClient((request) async {
          return http.Response(
            jsonEncode({'items': dummyNotes}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(
            body: LinkExistingNotesDialog(
              ticketId: 'ticket-100',
              ticketDisplayNumber: '54321',
              alreadyLinkedNoteIds: const ['note-3'],
              activeUser: 'EOLIVA',
              close: ([_]) {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Filtro "Mis Notas"
      final misNotasTab = find.text('Mis Notas');
      expect(misNotasTab, findsOneWidget);
      await tester.tap(misNotasTab);
      await tester.pump();

      // Solo note-1 (propiedad de EOLIVA) debe aparecer
      expect(find.text('Análisis de Incidencia de Pagos'), findsOneWidget);
      expect(find.text('Script de rollback y contingencia'), findsNothing);

      // Filtro "Compartidas"
      final compartidasTab = find.text('Compartidas');
      expect(compartidasTab, findsOneWidget);
      await tester.tap(compartidasTab);
      await tester.pump();

      // Solo note-2 (propiedad de JPEREZ, compartida con EOLIVA) debe aparecer
      expect(find.text('Análisis de Incidencia de Pagos'), findsNothing);
      expect(find.text('Script de rollback y contingencia'), findsOneWidget);

      // Regresar a "Todas"
      await tester.tap(find.text('Todas'));
      await tester.pump();

      // Probar búsqueda de texto
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'rollback');
      await tester.pump();

      expect(find.text('Script de rollback y contingencia'), findsOneWidget);
      expect(find.text('Análisis de Incidencia de Pagos'), findsNothing);
    },
  );

  testWidgets(
    'Selección múltiple y botón Vincular seleccionadas asocian las notas correctamente',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      NoteService.setHttpClientForTesting(
        MockClient((request) async {
          return http.Response(
            jsonEncode({'items': dummyNotes}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final associatedNotes = <String>[];
      DeployTicketService.setHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.contains('/notas/')) {
            final segments = request.url.pathSegments;
            final noteId = segments.last;
            associatedNotes.add(noteId);
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'id': 'ticket-100', 'noteIds': associatedNotes},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      List<String>? closedResult;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Scaffold(
            body: LinkExistingNotesDialog(
              ticketId: 'ticket-100',
              ticketDisplayNumber: '54321',
              alreadyLinkedNoteIds: const ['note-3'],
              activeUser: 'EOLIVA',
              close: ([res]) => closedResult = res,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Seleccionar visibles con el checkbox superior
      final selectAllTapTarget = find.text('Seleccionar visibles (2)');
      expect(selectAllTapTarget, findsOneWidget);
      await tester.tap(selectAllTapTarget);
      await tester.pump();

      expect(find.text('2 seleccionadas'), findsOneWidget);

      final linkBtn = find.text('Vincular 2 notas');
      expect(linkBtn, findsOneWidget);

      await tester.tap(linkBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Al incluir note-2 que ya pertenecía al ticket 999, aparece advertencia de reasignación
      expect(find.text('Reasignación de Notas'), findsOneWidget);

      // Confirmar reasignación
      final confirmBtn = find.text('Reasignar y Vincular');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(associatedNotes, contains('note-1'));
      expect(associatedNotes, contains('note-2'));
      expect(closedResult, contains('note-1'));
      expect(closedResult, contains('note-2'));

      ConnectionStatusService.instance.stopHeartbeatForTesting();
    },
  );
}
