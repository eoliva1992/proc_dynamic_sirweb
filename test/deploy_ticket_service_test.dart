import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/models/deploy_ticket.dart';
import 'package:proc_dynamic_sirweb/services/deploy_ticket_service.dart';
import 'package:proc_dynamic_sirweb/services/server_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('DeployTicketService baseUrl matches ServerConfigService', () async {
    await ServerConfigService().setBaseUrl('http://localhost:5180');
    final url = await DeployTicketService.getBaseUrl();
    expect(url, 'http://localhost:5180/tools/ticket-despliegue');
  });

  test(
    'Contratos JSON de creación y modificación cumplen con curl especificado',
    () {
      final ticket = DeployTicket(
        id: 'guid-123',
        version: 1,
        autoriza: 'ARTORRES',
        tipoSolicitud: 'Freshserver',
        numeroSolicitud: 'INC-56430',
        usuarioCrea: 'EOLIVA',
        usuarioActualiza: 'EOLIVA',
        url: '//dev.azure.com/humanoseguros/SirWeb/_workitems/edit/331974',
        reglasNegocio: ['RN_1', 'RN_2'],
        paquetes: ['PCK_1'],
        funciones: ['FN_1'],
        sql: [
          DeployTicketScript(nombre: 'script22102026', contenido: 'SELECT 1;'),
        ],
        reverseSql: [
          DeployTicketScript(nombre: 'rev.yaml', contenido: 'table: TABLA'),
        ],
        objetos: ['OBJ_1'],
        triggers: ['TRG_1'],
        bloqueLogico: [
          DeployTicketScript(nombre: 'BLK_1', contenido: 'BEGIN NULL; END;'),
        ],
        database: 'DESA',
        databaseDestino: 'PROD',
      );

      final createPayload = ticket.toJsonForCreate();
      expect(createPayload['id'], isNull);
      expect(createPayload['version'], 1);
      expect(createPayload['autoriza'], 'ARTORRES');
      expect(createPayload['tipoSolicitud'], 'Freshserver');
      expect(createPayload['numeroSolicitud'], 'INC-56430');
      expect(createPayload['usuarioCrea'], 'EOLIVA');
      expect(createPayload['reglasNegocio'], 'RN_1,RN_2');
      expect(createPayload['database'], 'DESA');
      expect(createPayload['databaseDestino'], 'PROD');

      final updatePayload = ticket.toJsonForUpdate();
      expect(updatePayload.containsKey('id'), isFalse);
      expect(updatePayload['usuarioActualiza'], 'EOLIVA');
      expect(updatePayload['database'], 'DESA');
      expect(updatePayload['databaseDestino'], 'PROD');
      expect(
        updatePayload['sql'],
        equals([
          {'nombre': 'script22102026', 'contenido': 'SELECT 1;'},
        ]),
      );
      expect(
        updatePayload['bloqueLogico'],
        equals([
          {'nombre': 'BLK_1', 'contenido': 'BEGIN NULL; END;'},
        ]),
      );
    },
  );
}
