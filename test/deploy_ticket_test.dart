import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/deploy_ticket.dart';

void main() {
  group('DeployTicket', () {
    test('fromJson y toJsonForCreate / toJsonForUpdate', () {
      final jsonSample = {
        'id': 'abc-123',
        'version': 1,
        'autoriza': 'ARTORRES',
        'url': '//dev.azure.com/humanoseguros/SirWeb/_workitems/edit/331974',
        'tipoSolicitud': 'Freshserver',
        'numeroSolicitud': 'INC-56430',
        'reglasNegocio': ['RN_CALCULO', 'RN_EMISION'],
        'paquetes': ['PKG_COTIZA'],
        'funciones': ['FN_VALIDA'],
        'sql': [
          {
            'id': 'sql-1',
            'nombre': 'script22102026',
            'contenido': 'ALTER TABLE TEST ADD COL NUMBER;',
            'createdAt': '2026-10-26T12:23:22.962Z',
          },
        ],
        'reverseSql': [
          {
            'id': 'rsql-1',
            'nombre': 'rev_insert.yaml',
            'contenido':
                'dbconfig:\n  tables:\n    - dml: merge\n      name: test',
          },
        ],
        'objetos': ['TY_DATOS'],
        'triggers': ['TRG_AUDIT'],
        'bloqueLogico': [
          {'id': 'blk-1', 'nombre': 'BLK_1', 'contenido': 'BEGIN NULL; END;'},
        ],
        'database': 'DESA',
        'databaseDestino': 'PROD',
        'rutaDirectorioLocal': 'C:\\Proyectos\\Scripts',
        'rutaRepositorio': 'C:\\Proyectos\\Repo',
        'usuarioCrea': 'EOLIVA',
        'usuarioActualiza': 'ARTORRES',
        'fechaCreacion': '2026-10-26T00:55:34.718Z',
        'fechaModificacion': '2026-10-26T01:10:00.000Z',
      };

      final ticket = DeployTicket.fromJson(jsonSample);

      expect(ticket.id, 'abc-123');
      expect(ticket.autoriza, 'ARTORRES');
      expect(ticket.tipoSolicitud, 'Freshserver');
      expect(ticket.numeroSolicitud, 'INC-56430');
      expect(ticket.rutaDirectorioLocal, 'C:\\Proyectos\\Scripts');
      expect(ticket.rutaRepositorio, 'C:\\Proyectos\\Repo');
      expect(ticket.reglasNegocio, ['RN_CALCULO', 'RN_EMISION']);
      expect(ticket.paquetes, ['PKG_COTIZA']);
      expect(ticket.sqlNames, ['script22102026']);
      expect(ticket.sql.first.contenido, 'ALTER TABLE TEST ADD COL NUMBER;');
      expect(ticket.reverseSqlNames, ['rev_insert.yaml']);
      expect(ticket.bloqueLogicoNames, ['BLK_1']);
      expect(ticket.bloqueLogico.first.contenido, 'BEGIN NULL; END;');
      expect(ticket.database, 'DESA');
      expect(ticket.databaseDestino, 'PROD');
      expect(ticket.isPersisted, isTrue);

      final createJson = ticket.toJsonForCreate();
      expect(createJson['id'], isNull);
      expect(createJson['autoriza'], 'ARTORRES');
      expect(createJson['rutaDirectorioLocal'], 'C:\\Proyectos\\Scripts');
      expect(createJson['rutaRepositorio'], 'C:\\Proyectos\\Repo');
      expect(createJson['reglasNegocio'], 'RN_CALCULO,RN_EMISION');
      expect(createJson['usuarioCrea'], 'EOLIVA');
      expect(createJson['sql'], [
        {
          'id': 'sql-1',
          'nombre': 'script22102026',
          'contenido': 'ALTER TABLE TEST ADD COL NUMBER;',
        },
      ]);
      expect(createJson['reverseSql'], [
        {
          'id': 'rsql-1',
          'nombre': 'rev_insert.yaml',
          'contenido':
              'dbconfig:\n  tables:\n    - dml: merge\n      name: test',
        },
      ]);
      expect(createJson['bloqueLogico'], [
        {'id': 'blk-1', 'nombre': 'BLK_1', 'contenido': 'BEGIN NULL; END;'},
      ]);

      final updateJson = ticket.toJsonForUpdate();
      expect(updateJson['autoriza'], 'ARTORRES');
      expect(updateJson['usuarioActualiza'], 'ARTORRES');
      expect(updateJson['database'], 'DESA');
      expect(updateJson['rutaDirectorioLocal'], 'C:\\Proyectos\\Scripts');
      expect(updateJson['rutaRepositorio'], 'C:\\Proyectos\\Repo');
      expect(updateJson['databaseDestino'], 'PROD');
      expect(updateJson['reglasNegocio'], 'RN_CALCULO,RN_EMISION');
      expect(updateJson['sql'], [
        {
          'id': 'sql-1',
          'nombre': 'script22102026',
          'contenido': 'ALTER TABLE TEST ADD COL NUMBER;',
        },
      ]);
      expect(updateJson['bloqueLogico'], [
        {'id': 'blk-1', 'nombre': 'BLK_1', 'contenido': 'BEGIN NULL; END;'},
      ]);
    });

    test(
      'parseIndexTxt procesa un archivo index.txt real con comentarios y saltos',
      () {
        const indexContent = '''
# ARCHIVO DE CONFIGURACION PARA PASES POR GIT SIRWEB 
# Claves reservadas:
# V, AUT, URL, TPSOL, NUSOL, RN, PROC, PCK, FUN, SQL, RSQL, OBJ, TRG, BLK, DB, DBD
V:1
AUT:ARTORRES
URL://dev.azure.com/humanoseguros/SirWeb/_workitems/edit/331974
TPSOL:Freshserver
NUSOL:INC-56430
SQL:script22102026
RN:PR_REGLA_1, PR_REGLA_2
PROC:PR_REGLA_3
PCK:PKG_TEST
DB:DESA
DBD:PROD
''';

        final ticket = DeployTicket.parseIndexTxt(
          indexContent,
          currentUser: 'EOLIVA',
        );

        expect(ticket.version, 1);
        expect(ticket.autoriza, 'ARTORRES');
        expect(
          ticket.url,
          '//dev.azure.com/humanoseguros/SirWeb/_workitems/edit/331974',
        );
        expect(ticket.tipoSolicitud, 'Freshserver');
        expect(ticket.numeroSolicitud, 'INC-56430');
        expect(ticket.sqlNames, ['script22102026']);
        expect(ticket.reglasNegocio, [
          'PR_REGLA_1',
          'PR_REGLA_2',
          'PR_REGLA_3',
        ]);
        expect(ticket.paquetes, ['PKG_TEST']);
        expect(ticket.database, 'DESA');
        expect(ticket.databaseDestino, 'PROD');
        expect(ticket.usuarioCrea, 'EOLIVA');

        final generated = ticket.toIndexTxt();
        expect(generated.contains('V:1'), isTrue);
        expect(generated.contains('AUT:ARTORRES'), isTrue);
        expect(generated.contains('TPSOL:Freshserver'), isTrue);
        expect(generated.contains('NUSOL:INC-56430'), isTrue);
        expect(generated.contains('SQL:script22102026'), isTrue);
        expect(
          generated.contains('RN:PR_REGLA_1,PR_REGLA_2,PR_REGLA_3'),
          isTrue,
        );
      },
    );
  });
}
