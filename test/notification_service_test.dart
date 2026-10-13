import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/app_notification.dart';
import 'package:proc_dynamic_sirweb/services/notification_service.dart';

void main() {
  group('NotificationService & AppNotification tests', () {
    test('AppNotification.fromJson parses standard json payload', () {
      final json = {
        'id': 'notif-123',
        'title': 'Nota compartida',
        'message': 'Juan compartió la nota "Arquitectura" contigo.',
        'kind': 'Info',
        'source': 'CompartirNota',
        'timestamp': '2026-04-14T10:00:00Z',
        'data': {
          'noteId': 'note-abc-999',
          'ownerUser': 'JUAN',
          'permission': 'Edit',
        },
      };

      final notif = AppNotification.fromJson(json);
      expect(notif.id, equals('notif-123'));
      expect(notif.title, equals('Nota compartida'));
      expect(notif.message, contains('Juan compartió'));
      expect(notif.kind, equals(AppNotificationKind.info));
      expect(notif.data?['noteId'], equals('note-abc-999'));
      expect(notif.read, isFalse);
    });

    test('AppNotification.fromJson parses REST API payload format', () {
      final json = {
        'id': 'notif-rest-456',
        'group': 'EOLIVA',
        'kind': 1,
        'source': 'ProcesoBatch',
        'message': 'Cálculo de póliza finalizado con éxito',
        'operationId': 'op-999',
        'percent': 100.0,
        'dataJson': '{"poliza": 12345}',
        'createdAt': '2026-10-11T03:55:17.679Z',
        'readAt': null,
      };

      final notif = AppNotification.fromJson(json);
      expect(notif.id, equals('notif-rest-456'));
      expect(notif.group, equals('EOLIVA'));
      expect(notif.kind, equals(AppNotificationKind.info));
      expect(notif.source, equals('ProcesoBatch'));
      expect(notif.message, equals('Cálculo de póliza finalizado con éxito'));
      expect(notif.operationId, equals('op-999'));
      expect(notif.percent, equals(100.0));
      expect(notif.data?['poliza'], equals(12345));
      expect(notif.read, isFalse);
      expect(notif.readAt, isNull);

      final readJson = Map<String, dynamic>.from(json);
      readJson['readAt'] = '2026-10-11T04:00:00.000Z';
      final readNotif = AppNotification.fromJson(readJson);
      expect(readNotif.read, isTrue);
      expect(readNotif.readAt, isNotNull);
    });

    test('NotificationPageResponse parses paginated items correctly', () {
      final pageJson = {
        'items': [
          {
            'id': 'item-1',
            'group': 'DEV',
            'kind': 2,
            'source': 'Sistema',
            'message': 'Operación completada',
            'operationId': null,
            'percent': null,
            'dataJson': null,
            'createdAt': '2026-10-11T03:55:17.679Z',
            'readAt': null,
          },
        ],
        'pagina': 1,
        'top': 50,
        'tieneSiguiente': true,
        'tienePrevio': false,
      };

      final page = NotificationPageResponse.fromJson(pageJson);
      expect(page.items.length, equals(1));
      expect(page.items.first.kind, equals(AppNotificationKind.success));
      expect(page.pagina, equals(1));
      expect(page.top, equals(50));
      expect(page.tieneSiguiente, isTrue);
      expect(page.tienePrevio, isFalse);
    });

    test(
      'NotificationService manages unread counts, markAsRead, and deleteNotification',
      () {
        final service = NotificationService.instance;
        service.clearAll();
        expect(service.unreadCount.value, equals(0));

        final n1 = AppNotification(
          id: '1',
          title: 'Aviso 1',
          message: 'Mensaje 1',
          timestamp: DateTime.now(),
        );
        final n2 = AppNotification(
          id: '2',
          title: 'Aviso 2',
          message: 'Mensaje 2',
          timestamp: DateTime.now(),
        );

        service.addNotification(n1, showToast: false);
        service.addNotification(n2, showToast: false);

        expect(service.notifications.value.length, equals(2));
        expect(service.unreadCount.value, equals(2));

        service.markAsRead('2');
        expect(service.unreadCount.value, equals(1));

        // Eliminar n1
        service.deleteNotification('1');
        expect(service.notifications.value.length, equals(1));
        expect(service.unreadCount.value, equals(0));

        service.clearAll();
        expect(service.notifications.value.isEmpty, isTrue);
      },
    );
  });
}
