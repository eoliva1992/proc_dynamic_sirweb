import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/services/sql_session_manager.dart';

void main() {
  group('SqlSessionManager', () {
    late SqlSessionManager manager;

    setUp(() {
      manager = SqlSessionManager.instance;
      manager.reset();
      manager.idleTimeout = const Duration(minutes: 30);
      procedimientosProvider.setCdUsuario('TESTUSER');
    });

    tearDown(() {
      manager.reset();
    });

    test('almacena y recupera sesión por clave compuesta (ambiente, owner)', () {
      manager.setSessionId('Desa', 'sess-100', owner: 'USER1');
      manager.setSessionId('Desa', 'sess-200', owner: 'USER2');

      expect(manager.getSessionId('Desa', owner: 'USER1'), 'sess-100');
      expect(manager.getSessionId('Desa', owner: 'USER2'), 'sess-200');
      expect(manager.getSessionId('QA', owner: 'USER1'), isNull);
    });

    test('reutiliza cdUsuario de procedimientosProvider si owner no es provisto', () {
      procedimientosProvider.setCdUsuario('GLOBALUSER');
      manager.setSessionId('Desa', 'sess-global');

      expect(manager.getSessionId('Desa'), 'sess-global');
      expect(manager.getSessionId('Desa', owner: 'GLOBALUSER'), 'sess-global');
      expect(manager.getSessionId('Desa', owner: 'OTHERUSER'), isNull);
    });

    test('preserva sessionId al marcar pendingChanges = false (COMMIT / ROLLBACK)', () {
      manager.setSessionId('Desa', 'sess-live', owner: 'USER1', hasPendingChanges: true);

      expect(manager.getSessionId('Desa', owner: 'USER1'), 'sess-live');
      expect(manager.hasPendingChanges('Desa', owner: 'USER1'), isTrue);

      // Simular commit/rollback
      manager.markPendingChanges('Desa', false, owner: 'USER1');

      expect(manager.getSessionId('Desa', owner: 'USER1'), 'sess-live');
      expect(manager.hasPendingChanges('Desa', owner: 'USER1'), isFalse);
    });

    test('clearSession elimina la sesión para el ambiente y owner especificados', () {
      manager.setSessionId('Desa', 'sess-desa', owner: 'USER1');
      manager.setSessionId('QA', 'sess-qa', owner: 'USER1');

      manager.clearSession('Desa', owner: 'USER1');

      expect(manager.getSessionId('Desa', owner: 'USER1'), isNull);
      expect(manager.getSessionId('QA', owner: 'USER1'), 'sess-qa');
    });

    test('expira automáticamente la sesión tras cumplirse el tiempo de inactividad', () async {
      manager.idleTimeout = const Duration(milliseconds: 50);
      manager.setSessionId('Desa', 'sess-expire', owner: 'USER1');

      expect(manager.getSessionId('Desa', owner: 'USER1'), 'sess-expire');

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(manager.getSessionId('Desa', owner: 'USER1'), isNull);
    });

    test('touch renueva el temporizador de inactividad evitando que expire tempranamente', () async {
      manager.idleTimeout = const Duration(milliseconds: 60);
      manager.setSessionId('Desa', 'sess-touch', owner: 'USER1');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      manager.touch('Desa', owner: 'USER1');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(manager.getSessionId('Desa', owner: 'USER1'), 'sess-touch');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(manager.getSessionId('Desa', owner: 'USER1'), isNull);
    });
  });
}
