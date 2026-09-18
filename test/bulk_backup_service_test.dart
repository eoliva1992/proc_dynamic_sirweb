import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/bulk_backup_item.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/services/bulk_backup_service.dart';

void main() {
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
    expect(script, contains("dbms_output.put_line(''ok'');"));
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
