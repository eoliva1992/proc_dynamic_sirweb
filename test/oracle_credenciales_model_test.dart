import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/oracle_credential.dart';

void main() {
  group('OracleCredentialStatus Tests', () {
    test('deserializa correctamente desde JSON', () {
      final json = {
        'ambiente': 'QA',
        'userId': 'SIRWEB_QA',
        'password': 'SecretPassword123',
        'host': '10.10.1.50',
        'port': '1521',
        'origen': 'Override',
      };

      final status = OracleCredentialStatus.fromJson(json);

      expect(status.ambiente, 'QA');
      expect(status.userId, 'SIRWEB_QA');
      expect(status.password, 'SecretPassword123');
      expect(status.host, '10.10.1.50');
      expect(status.port, '1521');
      expect(status.origen, 'Override');
      expect(status.isOverride, isTrue);
    });

    test('isOverride es false cuando el origen es Config', () {
      final json = {
        'ambiente': 'Desa',
        'userId': 'SIRWEB',
        'password': 'pwd',
        'origen': 'Config',
      };

      final status = OracleCredentialStatus.fromJson(json);
      expect(status.isOverride, isFalse);
    });

    test('serializa a JSON correctamente', () {
      const status = OracleCredentialStatus(
        ambiente: 'Prod',
        userId: 'PROD_USER',
        password: 'PROD_PASSWORD',
        host: 'prod-db.local',
        port: '1526',
        origen: 'Config',
      );

      final map = status.toJson();
      expect(map['ambiente'], 'Prod');
      expect(map['userId'], 'PROD_USER');
      expect(map['password'], 'PROD_PASSWORD');
      expect(map['host'], 'prod-db.local');
      expect(map['port'], '1526');
      expect(map['origen'], 'Config');
    });
  });

  group('OracleCredencialHistorialEntry Tests', () {
    test('deserializa entry de historial y parsea fecha UTC', () {
      final json = {
        'id': 'hist-1',
        'ambiente': 'QA',
        'cdUsuario': 'EOLIVA',
        'fechaCambioUtc': '2026-10-28T14:30:00Z',
        'accion': 'Actualizar',
        'userIdAntes': 'SIRWEB',
        'passwordAntes': 'old_pass',
        'userIdDespues': 'NUEVO_USER',
        'passwordDespues': 'new_pass',
        'hostAntes': '10.0.0.1',
        'puertoAntes': '1521',
        'hostDespues': '10.0.0.2',
        'puertoDespues': '1522',
      };

      final entry = OracleCredencialHistorialEntry.fromJson(json);

      expect(entry.id, 'hist-1');
      expect(entry.ambiente, 'QA');
      expect(entry.cdUsuario, 'EOLIVA');
      expect(entry.accion, 'Actualizar');
      expect(entry.userIdAntes, 'SIRWEB');
      expect(entry.userIdDespues, 'NUEVO_USER');
      expect(entry.hostAntes, '10.0.0.1');
      expect(entry.puertoAntes, '1521');
      expect(entry.hostDespues, '10.0.0.2');
      expect(entry.puertoDespues, '1522');
      expect(entry.fechaCambioUtc.isUtc, isTrue);
      expect(entry.fechaCambioUtc.year, 2026);
    });

    test('deserializa PagedResult correctamente', () {
      final json = {
        'items': [
          {
            'id': '1',
            'ambiente': 'Desa',
            'cdUsuario': 'USER1',
            'fechaCambioUtc': '2026-10-28T10:00:00Z',
            'accion': 'Restablecer',
            'userIdAntes': 'TEMP',
            'passwordAntes': 'pwd',
            'userIdDespues': 'ORIGINAL',
            'passwordDespues': 'pwd',
          },
        ],
        'total': 1,
        'pagina': 1,
        'top': 50,
      };

      final paged = OracleCredencialHistorialPagedResult.fromJson(json);
      expect(paged.total, 1);
      expect(paged.pagina, 1);
      expect(paged.items.length, 1);
      expect(paged.items.first.ambiente, 'Desa');
      expect(paged.items.first.accion, 'Restablecer');
    });
  });
}
