import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:proc_dynamic_sirweb/models/deploy_ticket.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/models/sql_http_trace.dart';
import 'package:proc_dynamic_sirweb/services/deploy_ticket_exporter_service.dart';
import 'package:proc_dynamic_sirweb/services/excel_exporter_service.dart';
import 'package:proc_dynamic_sirweb/services/sql_executor_service.dart';

class _FakeSqlExecutorService implements SqlExecutorService {
  @override
  void Function(SqlHttpTraceEntry)? onHttpTrace;

  _FakeSqlExecutorService();

  @override
  Future<SqlQueryResult> executeSelect(
    String sql, {
    required String ambiente,
    required String owner,
    String? sessionId,
    int maxRows = 1000,
    int timeoutSegundos = 30,
    http.Client? client,
    bool Function()? cancelado,
    void Function(SqlHttpTraceEntry)? onTrace,
  }) async {
    return const SqlQueryResult(
      columns: [
        SqlColumn(name: 'CD_PRODUCTO', dataType: 'NUMBER'),
        SqlColumn(name: 'DE_PRODUCTO', dataType: 'VARCHAR2'),
      ],
      rows: [
        [10, 'SEGURO MEDICO'],
      ],
      returnedRows: 1,
      truncated: false,
      durationMs: 5,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExcelExporterService', () {
    test('genera archivo XLSX válido con cabeceras y filas', () {
      final headers = ['NM_SCRIPT', 'FE_PASE', 'VERSION'];
      final rows = [
        ['01-eoliva-Calculo-20261026-V1.sql', '26/10/2026', 1],
        ['02-eoliva-ConfigReverse-20261026-V1.sql', '26/10/2026', 1],
      ];

      final bytes = ExcelExporterService.instance.generateXlsx(
        sheetName: 'Pase Git',
        headers: headers,
        rows: rows,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);

      // Descomprimir el archivo ZIP para verificar los archivos OpenXML generados
      final archive = ZipDecoder().decodeBytes(bytes);
      final fileNames = archive.files.map((f) => f.name).toList();

      expect(fileNames.contains('[Content_Types].xml'), isTrue);
      expect(fileNames.contains('xl/workbook.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet1.xml'), isTrue);
      expect(fileNames.contains('xl/styles.xml'), isTrue);

      final sheetXml = String.fromCharCodes(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
      );
      expect(sheetXml.contains('NM_SCRIPT'), isTrue);
      expect(sheetXml.contains('01-eoliva-Calculo-20261026-V1.sql'), isTrue);
      expect(
        sheetXml.contains('Pase Git'),
        isFalse,
      ); // el nombre está en workbook.xml

      final workbookXml = String.fromCharCodes(
        archive.findFile('xl/workbook.xml')!.content as List<int>,
      );
      expect(workbookXml.contains('name="Pase Git"'), isTrue);
    });
  });

  group('DeployTicketExporterService - Nombres y Utilidades', () {
    test(
      'sanitizeRuleName limpia guiones, números y caracteres especiales',
      () {
        expect(
          DeployTicketExporterService.sanitizeRuleName('PR_REGLA_CALCULO_1'),
          equals('PRREGLACALCULO'),
        );
        expect(
          DeployTicketExporterService.sanitizeRuleName('RN-EMISION_V2'),
          equals('RNEMISIONV'),
        );
        expect(
          DeployTicketExporterService.sanitizeRuleName('CotizaSugerida'),
          equals('CotizaSugerida'),
        );
      },
    );

    test(
      'formatDateYmd y formatTimestamp devuelven formatos esperados sin caracteres especiales',
      () {
        final date = DateTime(2026, 10, 22, 8, 58, 35);
        expect(
          DeployTicketExporterService.formatDateYmd(date),
          equals('20261022'),
        );
        expect(
          DeployTicketExporterService.formatTimestamp(date),
          equals('20261022085835'),
        );
        expect(
          DeployTicketExporterService.formatDateDdMmYyyy(date),
          equals('22/10/2026'),
        );
      },
    );

    test('capitalize transforma texto adecuadamente', () {
      expect(
        DeployTicketExporterService.capitalize('matriz'),
        equals('Matriz'),
      );
      expect(
        DeployTicketExporterService.capitalize('FRESHSERVER'),
        equals('Freshserver'),
      );
    });

    test('exportarTicket genera estructura completa de archivos y auditoría', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'deploy_export_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final ticket = DeployTicket(
        version: 1,
        autoriza: 'ARTORRES',
        url: '//dev.azure.com/humanoseguros/SirWeb/_workitems/edit/330701',
        tipoSolicitud: 'Matriz',
        numeroSolicitud: '1366',
        usuarioCrea: 'EOLIVA',
        database: 'DESA',
        databaseDestino: 'PROD',
        reglasNegocio: ['PR_REGLA_1'],
        paquetes: ['PKG_TEST'],
        funciones: ['FN_CALC'],
        triggers: ['TRG_AUDIT'],
        objetos: ['TP_ITEM'],
        sql: [
          DeployTicketScript(
            nombre: 'migracion.sql',
            contenido: 'SELECT 1 FROM DUAL;',
          ),
        ],
        reverseSql: [
          DeployTicketScript(
            nombre: 'rev_config.yaml',
            contenido:
                'dbconfig:\n  tables:\n    - name: test_tbl\n      dml: merge',
          ),
        ],
        bloqueLogico: [DeployTicketScript(nombre: 'BLK_1', contenido: 'NULL;')],
      );

      final exporter = DeployTicketExporterService();
      final files = await exporter.exportarTicket(
        ticket: ticket,
        targetDirectoryPath: tempDir.path,
      );

      expect(files.isNotEmpty, isTrue);

      final fileNames = files.map((f) => f.nombreArchivo).toList();

      // Debe incluir script RN (sin guiones/underscores en nombre de regla, con fecha yyyymmdd)
      final rnFile = fileNames.firstWhere((n) => n.contains('PRREGLA'));
      expect(rnFile, matches(r'^\d{2}-eoliva-PRREGLA-\d{8}-V1\.sql$'));

      // Debe incluir script SQL
      final sqlFile = fileNames.firstWhere((n) => n.contains('migracion'));
      expect(sqlFile, matches(r'^\d{2}-eoliva-migracion-\d{8}-V1\.sql$'));

      // Debe incluir script RSQL
      final rsqlFile = fileNames.firstWhere(
        (n) => n.contains('rev_configReverse'),
      );
      expect(
        rsqlFile,
        matches(r'^\d{2}-eoliva-rev_configReverse\d{8}-\d{8}-V1\.sql$'),
      );

      // Debe incluir Paquete PAQUETE.sql
      expect(fileNames.contains('PKG_TEST.sql'), isTrue);

      // Debe incluir Funciones, Triggers y Objetos con DUENO.NOMBRE.sql
      expect(fileNames.any((n) => n.endsWith('.FN_CALC.sql')), isTrue);
      expect(fileNames.any((n) => n.endsWith('.TRG_AUDIT.sql')), isTrue);
      expect(fileNames.any((n) => n.endsWith('.TP_ITEM.sql')), isTrue);

      // Debe incluir BLK envuelto en block-usuario-nombre-ddmmyyyy-yyyymmdd-Vversion.sql
      final blkFile = fileNames.firstWhere(
        (n) => n.startsWith('block-eoliva-BLK_1'),
      );
      expect(blkFile, matches(r'^block-eoliva-BLK_1\d{8}-\d{8}-V1\.sql$'));

      // La carpeta final debe llamarse PaseScriptAmbiente+fecha(yyyymmdd)+_+numeroSolicitud
      final todayYmd = DeployTicketExporterService.formatDateYmd(
        DateTime.now(),
      );
      final targetFolder = Directory(
        '${tempDir.path}/PaseScriptAmbiente${todayYmd}_1366',
      );
      expect(await targetFolder.exists(), isTrue);

      // Todos los archivos generados deben residir directamente dentro de PaseScriptAmbiente+fecha(yyyymmdd)+_+numeroSolicitud
      expect(await File('${targetFolder.path}/$rnFile').exists(), isTrue);
      expect(await File('${targetFolder.path}/$sqlFile').exists(), isTrue);

      // Debe incluir el Excel pase_archivo_timestamp.xlsx directamente en esa carpeta
      final excelFile = fileNames.firstWhere(
        (n) => n.startsWith('pase_archivo_') && n.endsWith('.xlsx'),
      );
      expect(excelFile, isNotNull);
      expect(await File('${targetFolder.path}/$excelFile').exists(), isTrue);

      // Debe incluir el script de auditoría pase_script_timestamp.sql directamente en esa carpeta
      final auditFile = fileNames.firstWhere(
        (n) => n.startsWith('pase_script_') && n.endsWith('.sql'),
      );
      expect(auditFile, isNotNull);
      expect(await File('${targetFolder.path}/$auditFile').exists(), isTrue);

      final auditContent = await File(
        '${targetFolder.path}/$auditFile',
      ).readAsString();
      expect(auditContent.contains('INSERT INTO PASEAMBIENTESCRIPT'), isTrue);
      expect(auditContent.contains('ARTORRES'), isTrue);
      expect(auditContent.contains('EOLIVA'), isTrue);
      expect(auditContent.contains('Matriz'), isTrue);
      expect(auditContent.contains('1366'), isTrue);
      expect(auditContent.contains('330701'), isTrue);
    });

    test(
      'exportarTicket reemplaza el contenido previo si la carpeta PaseScriptAmbiente ya existe',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'deploy_export_replace_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final todayYmd = DeployTicketExporterService.formatDateYmd(
          DateTime.now(),
        );
        final targetFolder = Directory(
          '${tempDir.path}/PaseScriptAmbiente${todayYmd}_999',
        );
        await targetFolder.create(recursive: true);

        // Crear un archivo obsoleto en la carpeta
        final oldFile = File('${targetFolder.path}/archivo_obsoleto.txt');
        await oldFile.writeAsString('contenido antiguo');
        expect(await oldFile.exists(), isTrue);

        final ticket = DeployTicket(
          version: 1,
          autoriza: 'USER',
          tipoSolicitud: 'Sysid',
          numeroSolicitud: '999',
          usuarioCrea: 'DEV',
          database: 'DESA',
          databaseDestino: 'PROD',
          reglasNegocio: ['RN_TEST'],
        );

        final exporter = DeployTicketExporterService();
        final files = await exporter.exportarTicket(
          ticket: ticket,
          targetDirectoryPath: tempDir.path,
        );

        // La carpeta debe existir y el archivo antiguo debe haber sido eliminado/reemplazado
        expect(await targetFolder.exists(), isTrue);
        expect(await oldFile.exists(), isFalse);
        expect(files.isNotEmpty, isTrue);
      },
    );

    test(
      'exportarTicket genera PaseScriptAmbiente sin guion bajo cuando no hay numeroSolicitud',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'deploy_export_no_num_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final todayYmd = DeployTicketExporterService.formatDateYmd(
          DateTime.now(),
        );
        final targetFolder = Directory(
          '${tempDir.path}/PaseScriptAmbiente$todayYmd',
        );

        final ticket = DeployTicket(
          version: 1,
          autoriza: 'USER',
          tipoSolicitud: 'Sysid',
          numeroSolicitud: '',
          usuarioCrea: 'DEV',
          database: 'DESA',
          databaseDestino: 'PROD',
          reglasNegocio: ['RN_TEST'],
        );

        final exporter = DeployTicketExporterService();
        final files = await exporter.exportarTicket(
          ticket: ticket,
          targetDirectoryPath: tempDir.path,
        );

        expect(await targetFolder.exists(), isTrue);
        expect(files.isNotEmpty, isTrue);
      },
    );

    test(
      'exportarTicket genera UPDATE en vez de MERGE cuando dml es update',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'deploy_export_update_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final ticket = DeployTicket(
          version: 1,
          autoriza: 'USER',
          tipoSolicitud: 'Sysid',
          numeroSolicitud: '999',
          usuarioCrea: 'DEV',
          database: 'DESA',
          databaseDestino: 'PROD',
          reverseSql: [
            DeployTicketScript(
              nombre: 'config_reverse.yaml',
              contenido: '''dbconfig:
  tables:
    - name: PRODUCTO
      dml: update
      columns: DE_PRODUCTO
      filters:
        CD_PRODUCTO: "= 10"
''',
            ),
          ],
        );

        final exporter = DeployTicketExporterService(
          sqlExecutorService: _FakeSqlExecutorService(),
        );
        final files = await exporter.exportarTicket(
          ticket: ticket,
          targetDirectoryPath: tempDir.path,
        );

        final rsqlExported = files.firstWhere((f) => f.categoria == 'RSQL');
        final rsqlContent = await File(
          rsqlExported.rutaCompleta,
        ).readAsString();

        // Debe generar UPDATE con WHERE según la condición especificada y no MERGE
        expect(rsqlContent.contains('UPDATE PRODUCTO SET'), isTrue);
        expect(rsqlContent.contains('WHERE CD_PRODUCTO = 10'), isTrue);
        expect(rsqlContent.contains('MERGE INTO PRODUCTO'), isFalse);
      },
    );

    test('MERGE no debe actualizar Primary Keys en UPDATE SET', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'deploy_export_merge_pk_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final ticket = DeployTicket(
        version: 1,
        autoriza: 'USER',
        tipoSolicitud: 'Sysid',
        numeroSolicitud: '999',
        usuarioCrea: 'DEV',
        database: 'DESA',
        databaseDestino: 'PROD',
        reverseSql: [
          DeployTicketScript(
            nombre: 'config_reverse_merge.yaml',
            contenido: '''dbconfig:
  tables:
    - name: PRODUCTO
      dml: merge
      filters:
        CD_PRODUCTO: "= 10"
''',
          ),
        ],
      );

      final exporter = DeployTicketExporterService(
        sqlExecutorService: _FakeSqlExecutorService(),
      );
      final files = await exporter.exportarTicket(
        ticket: ticket,
        targetDirectoryPath: tempDir.path,
      );

      final rsqlExported = files.firstWhere((f) => f.categoria == 'RSQL');
      final rsqlContent = await File(rsqlExported.rutaCompleta).readAsString();

      expect(rsqlContent.contains('MERGE INTO PRODUCTO'), isTrue);
      expect(
        rsqlContent.contains('ON (T.CD_PRODUCTO = S.CD_PRODUCTO)'),
        isTrue,
      );
      // En UPDATE SET NO debe aparecer la PK ni la clave de ON
      expect(
        rsqlContent.contains('UPDATE SET T.DE_PRODUCTO = S.DE_PRODUCTO'),
        isTrue,
      );
      expect(
        rsqlContent.contains('UPDATE SET T.CD_PRODUCTO = S.CD_PRODUCTO'),
        isFalse,
      );
    });

    test('UPDATE no debe actualizar Primary Keys en SET', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'deploy_export_update_pk_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final ticket = DeployTicket(
        version: 1,
        autoriza: 'USER',
        tipoSolicitud: 'Sysid',
        numeroSolicitud: '999',
        usuarioCrea: 'DEV',
        database: 'DESA',
        databaseDestino: 'PROD',
        reverseSql: [
          DeployTicketScript(
            nombre: 'config_reverse_upd.yaml',
            contenido: '''dbconfig:
  tables:
    - name: PRODUCTO
      dml: update
      filters:
        CD_PRODUCTO: "= 10"
''',
          ),
        ],
      );

      final exporter = DeployTicketExporterService(
        sqlExecutorService: _FakeSqlExecutorService(),
      );
      final files = await exporter.exportarTicket(
        ticket: ticket,
        targetDirectoryPath: tempDir.path,
      );

      final rsqlExported = files.firstWhere((f) => f.categoria == 'RSQL');
      final rsqlContent = await File(rsqlExported.rutaCompleta).readAsString();

      // Debe actualizar solo DE_PRODUCTO, y CD_PRODUCTO debe estar solo en el WHERE
      expect(
        rsqlContent.contains(
          "UPDATE PRODUCTO SET DE_PRODUCTO = 'SEGURO MEDICO' WHERE CD_PRODUCTO = 10;",
        ),
        isTrue,
      );
      expect(rsqlContent.contains('CD_PRODUCTO = 10,'), isFalse);
    });

    test(
      'formatSqlStringOrClob fragmenta cadenas mayores a 3000 caracteres en bloques TO_CLOB',
      () {
        final hugeText = 'X' * 6500;
        final formatted = DeployTicketExporterService.formatSqlStringOrClob(
          hugeText,
          isClob: true,
        );
        expect(
          formatted,
          contains(
            "TO_CLOB('${'X' * 3000}') || TO_CLOB('${'X' * 3000}') || TO_CLOB('${'X' * 500}')",
          ),
        );
      },
    );

    test(
      'formatSqlStringOrClob envuelve CLOB <= 3000 en TO_CLOB y string normal en comillas simples',
      () {
        expect(
          DeployTicketExporterService.formatSqlStringOrClob(
            'HOLA',
            isClob: false,
          ),
          "'HOLA'",
        );
        expect(
          DeployTicketExporterService.formatSqlStringOrClob(
            'HOLA',
            isClob: true,
          ),
          "TO_CLOB('HOLA')",
        );
      },
    );

    test(
      'crearDirectorioYArchivos genera carpeta, index.txt y archivos SQL de scripts',
      () async {
        final tempBase = await Directory.systemTemp.createTemp(
          'deploy_create_files_test_',
        );
        addTearDown(() => tempBase.delete(recursive: true));

        const ticket = DeployTicket(
          id: 'ticket-test-local',
          version: 2,
          autoriza: 'TESTUSER',
          url:
              'https://dev.azure.com/humanoseguros/SirWeb/_workitems/edit/44219',
          tipoSolicitud: 'Matriz',
          numeroSolicitud: '1234',
          sql: [
            DeployTicketScript(
              id: 'sql-1',
              nombre: 'alter_table_clientes.sql',
              contenido: 'ALTER TABLE CLIENTES ADD (ACTIVO NUMBER(1));',
            ),
          ],
          reverseSql: [
            DeployTicketScript(
              id: 'rsql-1',
              nombre: 'reversa_clientes.sql',
              contenido: 'ALTER TABLE CLIENTES DROP COLUMN ACTIVO;',
            ),
          ],
          bloqueLogico: [
            DeployTicketScript(
              id: 'blk-1',
              nombre: 'bloque_inicial',
              contenido: 'DBMS_OUTPUT.PUT_LINE(1);',
            ),
          ],
          reglasNegocio: ['PR_TEST_REG'],
        );

        final exporter = DeployTicketExporterService.instance;
        final files = await exporter.crearDirectorioYArchivos(
          ticket: ticket,
          rootDirectoryPath: tempBase.path,
          folderName: ticket.suggestedFolderName,
        );

        expect(ticket.suggestedFolderName, '44219_1234');

        final targetFolder = Directory(
          '${tempBase.path}${Platform.pathSeparator}44219_1234',
        );
        expect(await targetFolder.exists(), isTrue);

        final indexFile = File(
          '${targetFolder.path}${Platform.pathSeparator}index.txt',
        );
        expect(await indexFile.exists(), isTrue);
        final indexText = await indexFile.readAsString();
        expect(indexText.contains('V:2'), isTrue);
        expect(indexText.contains('AUT:TESTUSER'), isTrue);
        expect(indexText.contains('NUSOL:1234'), isTrue);

        final sqlFile = File(
          '${targetFolder.path}${Platform.pathSeparator}alter_table_clientes.sql',
        );
        expect(await sqlFile.exists(), isTrue);
        expect(
          await sqlFile.readAsString(),
          'ALTER TABLE CLIENTES ADD (ACTIVO NUMBER(1));',
        );

        final rsqlFile = File(
          '${targetFolder.path}${Platform.pathSeparator}reversa_clientes.sql',
        );
        expect(await rsqlFile.exists(), isTrue);
        expect(
          await rsqlFile.readAsString(),
          'ALTER TABLE CLIENTES DROP COLUMN ACTIVO;',
        );

        final blkFile = File(
          '${targetFolder.path}${Platform.pathSeparator}bloque_inicial.sql',
        );
        expect(await blkFile.exists(), isTrue);

        final rnFile = File(
          '${targetFolder.path}${Platform.pathSeparator}PR_TEST_REG.sql',
        );
        expect(await rnFile.exists(), isTrue);

        expect(files.length, greaterThanOrEqualTo(5));
      },
    );

    test(
      'crearDirectorioYArchivos preserva extensiones originales (.yaml, .yml) y no duplica .sql',
      () async {
        final tempBase = await Directory.systemTemp.createTemp(
          'deploy_preserve_ext_test_',
        );
        addTearDown(() => tempBase.delete(recursive: true));

        const ticket = DeployTicket(
          id: 'ticket-test-yaml-ext',
          version: 1,
          autoriza: 'TESTUSER',
          tipoSolicitud: 'Matriz',
          numeroSolicitud: '9999',
          sql: [
            DeployTicketScript(
              id: 'sql-1',
              nombre: 'script_con_extension.sql',
              contenido: 'SELECT 1 FROM DUAL;',
            ),
            DeployTicketScript(
              id: 'sql-2',
              nombre: 'script_sin_extension',
              contenido: 'SELECT 2 FROM DUAL;',
            ),
          ],
          reverseSql: [
            DeployTicketScript(
              id: 'rsql-yaml',
              nombre: 'config.yaml',
              contenido: 'version: 1\ntables: []',
            ),
            DeployTicketScript(
              id: 'rsql-yml',
              nombre: 'filtros.yml',
              contenido: 'version: 1\ntables: []',
            ),
            DeployTicketScript(
              id: 'rsql-raw',
              nombre: 'reversa_datos',
              contenido: 'version: 1\ntables: []',
            ),
          ],
          reglasNegocio: ['RN_PRECIO.sql', 'RN_DESCUENTO'],
        );

        final exporter = DeployTicketExporterService.instance;
        final files = await exporter.crearDirectorioYArchivos(
          ticket: ticket,
          rootDirectoryPath: tempBase.path,
          folderName: 'ticket_ext_test',
        );

        final targetFolder = Directory(
          '${tempBase.path}${Platform.pathSeparator}ticket_ext_test',
        );
        expect(await targetFolder.exists(), isTrue);

        // Archivos esperados
        final yamlFile = File(
          '${targetFolder.path}${Platform.pathSeparator}config.yaml',
        );
        expect(
          await yamlFile.exists(),
          isTrue,
          reason: 'config.yaml debe mantenerse con su extensión original',
        );

        // Asegurar que no se creó config.yaml.sql
        final badYamlSql = File(
          '${targetFolder.path}${Platform.pathSeparator}config.yaml.sql',
        );
        expect(
          await badYamlSql.exists(),
          isFalse,
          reason: 'NO debe crear config.yaml.sql',
        );

        final ymlFile = File(
          '${targetFolder.path}${Platform.pathSeparator}filtros.yml',
        );
        expect(await ymlFile.exists(), isTrue);

        final badYmlSql = File(
          '${targetFolder.path}${Platform.pathSeparator}filtros.yml.sql',
        );
        expect(await badYmlSql.exists(), isFalse);

        final rawRsqlFile = File(
          '${targetFolder.path}${Platform.pathSeparator}reversa_datos.yaml',
        );
        expect(
          await rawRsqlFile.exists(),
          isTrue,
          reason: 'RSQL sin extensión debe adoptar .yaml por defecto',
        );

        final sqlWithExt = File(
          '${targetFolder.path}${Platform.pathSeparator}script_con_extension.sql',
        );
        expect(await sqlWithExt.exists(), isTrue);

        final sqlWithoutExt = File(
          '${targetFolder.path}${Platform.pathSeparator}script_sin_extension.sql',
        );
        expect(await sqlWithoutExt.exists(), isTrue);

        final rnWithExt = File(
          '${targetFolder.path}${Platform.pathSeparator}RN_PRECIO.sql',
        );
        expect(await rnWithExt.exists(), isTrue);

        final rnWithoutExt = File(
          '${targetFolder.path}${Platform.pathSeparator}RN_DESCUENTO.sql',
        );
        expect(await rnWithoutExt.exists(), isTrue);

        expect(files.any((f) => f.nombreArchivo == 'config.yaml'), isTrue);
        expect(files.any((f) => f.nombreArchivo == 'config.yaml.sql'), isFalse);
      },
    );
  });
}
