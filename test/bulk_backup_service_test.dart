import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/bulk_backup_item.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/services/backup_service.dart';
import 'package:proc_dynamic_sirweb/services/bulk_backup_service.dart';

void main() {
  group('BackupService.extractOwnerFromDdl', () {
    test('extrae owner de PROCEDURE calificado', () {
      const ddl =
          'CREATE OR REPLACE PROCEDURE PRODUCTO.CALCULA_VALOR_DATO_MARSH_SOLUTIONS (P_ID NUMBER) AS BEGIN NULL; END;';
      expect(BackupService.extractOwnerFromDdl(ddl), 'PRODUCTO');
    });

    test('extrae owner con comillas dobles y espacios', () {
      const ddl =
          'CREATE OR REPLACE EDITIONABLE PROCEDURE "PRODUCTO" . "MI_PROC" AS BEGIN NULL; END;';
      expect(BackupService.extractOwnerFromDdl(ddl), 'PRODUCTO');
    });

    test('extrae owner de PACKAGE BODY', () {
      const ddl =
          'CREATE OR REPLACE PACKAGE BODY PRODUCTO.PKG_PRUEBA AS PROCEDURE PR1 IS BEGIN NULL; END; END;';
      expect(BackupService.extractOwnerFromDdl(ddl), 'PRODUCTO');
    });

    test('devuelve cadena vacía si no tiene esquema explícito', () {
      const ddl =
          'CREATE OR REPLACE PROCEDURE CALCULA_VALOR_DATO_MARSH_SOLUTIONS AS BEGIN NULL; END;';
      expect(BackupService.extractOwnerFromDdl(ddl), '');
    });
  });

  group('BulkBackupService.buildSchemaScript con synonyms', () {
    test('resuelve owner desde el DDL cuando item y synonym no tienen owner', () {
      const item = BulkBackupItem(
        name: 'CALCULA_VALOR_DATO_MARSH_SOLUTIONS',
        type: 'PROCEDURE',
        source: BulkBackupSource.schema,
      );
      const spec =
          'CREATE OR REPLACE PROCEDURE PRODUCTO.CALCULA_VALOR_DATO_MARSH_SOLUTIONS (\n  P_VALOR OUT VARCHAR2\n) AS BEGIN NULL; END;\n/';
      final script = BulkBackupService.buildSchemaScript(
        item: item,
        ambiente: 'DESA',
        spec: spec,
        synonyms: const [
          (
            synonymName: 'CALCULA_VALOR_DATO_MARSH_SOLUTIONS',
            isPublic: true,
            owner: '',
          ),
        ],
        config: const BulkBackupConfig(includeSynonyms: true),
      );

      expect(
        script,
        contains(
          'CREATE OR REPLACE PUBLIC SYNONYM CALCULA_VALOR_DATO_MARSH_SOLUTIONS FOR PRODUCTO.CALCULA_VALOR_DATO_MARSH_SOLUTIONS;',
        ),
      );
    });
  });

  group('BulkBackupItem', () {
    test('normaliza categorías conocidas y conserva tipos futuros', () {
      expect(
        const BulkBackupItem(
          name: 'P1',
          type: 'PROCEDURE',
          source: BulkBackupSource.schema,
        ).category,
        'procedures',
      );
      expect(
        const BulkBackupItem(
          name: 'P1',
          type: 'PROCEDURE_DYNAMIC',
          source: BulkBackupSource.dynamicProcedure,
        ).category,
        'procedure-dynamic',
      );
      expect(
        const BulkBackupItem(
          name: 'X',
          type: 'MATERIALIZED VIEW',
          source: BulkBackupSource.schema,
        ).category,
        'materialized-view',
      );
    });

    test('identifica el mismo objeto sin importar el caso', () {
      const first = BulkBackupItem(
        name: 'P1',
        type: 'procedure',
        source: BulkBackupSource.schema,
      );
      const second = BulkBackupItem(
        name: 'p1',
        type: 'PROCEDURE',
        source: BulkBackupSource.schema,
      );
      expect(first, second);
    });
  });

  test('genera MERGE dinámico con actualización e inserción', () {
    const procedure = Procedimiento(
      cdProcedimiento: 'P_TEST',
      deTexto: "BEGIN dbms_output.put_line('ok'); END;",
      inConfiguracion: 'D',
      version: 3,
      stProcedimiento: '1',
    );

    final script = BulkBackupService.buildDynamicScript(
      procedure,
      'QA',
      'USER1',
    );

    expect(script, contains('MERGE INTO SIR.PROCEDIMIENTODINAMICO'));
    expect(script, contains('WHEN MATCHED THEN UPDATE'));
    expect(script, contains('WHEN NOT MATCHED THEN INSERT'));
    expect(script, contains("q'[BEGIN dbms_output.put_line('ok'); END;]'"));
    expect(script, isNot(contains('COMMIT;')));
  });

  test('quita acentos de los nombres de archivo', () {
    expect(
      BulkBackupService.safeFileName('Regla_áéíóú_Ñandú'),
      'Regla_aeiou_Nandu',
    );
  });

  test('escribe cada objeto en su subcarpeta', () async {
    final root = await Directory.systemTemp.createTemp('bulk-backup-test-');
    addTearDown(() => root.delete(recursive: true));
    const item = BulkBackupItem(
      name: 'P_TEST',
      type: 'PROCEDURE',
      source: BulkBackupSource.schema,
    );

    final result = await BulkBackupService.writeAll(
      directory: root,
      ambiente: 'QA',
      items: const [item],
      scripts: {item.id: 'script'},
    );

    expect(result.failures, isEmpty);
    expect(result.written, hasLength(1));
    expect(File(result.written.single).readAsStringSync(), 'script');
    expect(
      result.written.single,
      contains('${Platform.pathSeparator}procedures${Platform.pathSeparator}'),
    );
  });

  test('cancela antes de escribir el siguiente objeto', () async {
    final root = await Directory.systemTemp.createTemp('bulk-backup-cancel-');
    addTearDown(() => root.delete(recursive: true));
    const first = BulkBackupItem(
      name: 'P_FIRST',
      type: 'PROCEDURE',
      source: BulkBackupSource.schema,
    );
    const second = BulkBackupItem(
      name: 'P_SECOND',
      type: 'PROCEDURE',
      source: BulkBackupSource.schema,
    );
    var cancelled = false;

    final result = await BulkBackupService.writeAll(
      directory: root,
      ambiente: 'QA',
      items: const [first, second],
      scripts: {first.id: 'first', second.id: 'second'},
      onProgress: (completed, _, _) {
        if (completed == 1) cancelled = true;
      },
      isCancelled: () => cancelled,
    );

    expect(result.written, hasLength(1));
    expect(result.written.single, contains('P_FIRST'));
  });
}
