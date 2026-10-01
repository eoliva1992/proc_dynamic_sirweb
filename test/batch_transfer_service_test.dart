import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/batch_transfer_result.dart';
import 'package:proc_dynamic_sirweb/models/bulk_backup_item.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/services/batch_transfer_service.dart';
import 'package:proc_dynamic_sirweb/services/transfer_service.dart';

class _FakeDynamicAdapter implements DynamicProcedureTransferAdapter {
  final bool Function(String cdProcedimiento, String targetAmbiente)? failWhen;
  final calls = <String>[];

  _FakeDynamicAdapter({this.failWhen});

  @override
  Future<TransferResult> transfer({
    required String cdProcedimiento,
    required String sourceCode,
    required String inConfiguracion,
    required String cdUsuario,
    required String targetAmbiente,
  }) async {
    calls.add('$cdProcedimiento->$targetAmbiente');
    if (failWhen?.call(cdProcedimiento, targetAmbiente) ?? false) {
      return (success: false, message: 'ORA-00001: fallo simulado');
    }
    return (
      success: true,
      message: 'Actualizado en $targetAmbiente correctamente',
    );
  }
}

class _FakeSchemaAdapter implements SchemaObjectTransferAdapter {
  final bool Function(BulkBackupItem item, String targetAmbiente)? failWhen;
  final calls = <String>[];

  _FakeSchemaAdapter({this.failWhen});

  @override
  Future<SchemaTransferOutcome> transfer({
    required BulkBackupItem item,
    required String sourceAmbiente,
    required String targetAmbiente,
    required bool transferGrants,
    required bool transferSynonyms,
  }) async {
    calls.add('${item.name}->$targetAmbiente');
    if (failWhen?.call(item, targetAmbiente) ?? false) {
      return (
        success: false,
        message: 'PLS-00103: error de compilación simulado',
      );
    }
    return (success: true, message: 'Creado/actualizado en $targetAmbiente');
  }
}

const _proc = Procedimiento(
  cdProcedimiento: 'DR_TEST',
  deTexto: 'BEGIN NULL; END;',
  inConfiguracion: 'REGLA',
  version: 1,
  stProcedimiento: '1',
);

BulkBackupItem _dynamicItem([Procedimiento proc = _proc]) => BulkBackupItem(
  name: proc.cdProcedimiento,
  type: 'PROCEDURE_DYNAMIC',
  source: BulkBackupSource.dynamicProcedure,
  procedimiento: proc,
);

BulkBackupItem _schemaItem(String name, {String type = 'PROCEDURE'}) =>
    BulkBackupItem(
      name: name,
      type: type,
      owner: 'SIR',
      source: BulkBackupSource.schema,
    );

void main() {
  group('BatchTransferService', () {
    test(
      'enruta procedimientos dinámicos y objetos de esquema al adaptador correcto',
      () async {
        final dynamicAdapter = _FakeDynamicAdapter();
        final schemaAdapter = _FakeSchemaAdapter();
        final service = BatchTransferService(
          dynamicAdapter: dynamicAdapter,
          schemaAdapter: schemaAdapter,
        );

        final results = <BatchTransferResult>[];
        await service.run(
          items: [_dynamicItem(), _schemaItem('OBJ_RECIBOS')],
          sourceAmbiente: 'Desa',
          targetAmbientes: ['QA'],
          cdUsuario: 'USER1',
          onResult: results.add,
        );

        expect(dynamicAdapter.calls, ['DR_TEST->QA']);
        expect(schemaAdapter.calls, ['OBJ_RECIBOS->QA']);
        // Cada elemento reporta running + resultado final.
        expect(results.where((r) => r.isSuccess), hasLength(2));
      },
    );

    test(
      'reporta error de compilación de un objeto de esquema sin abortar el lote',
      () async {
        final schemaAdapter = _FakeSchemaAdapter(
          failWhen: (item, target) => item.name == 'OBJ_ROTO',
        );
        final service = BatchTransferService(schemaAdapter: schemaAdapter);

        final results = <BatchTransferResult>[];
        await service.run(
          items: [_schemaItem('OBJ_ROTO'), _schemaItem('OBJ_OK')],
          sourceAmbiente: 'Desa',
          targetAmbientes: ['QA'],
          cdUsuario: 'USER1',
          onResult: results.add,
        );

        final finals = results.where((r) => !r.isRunning).toList();
        expect(finals, hasLength(2));
        expect(
          finals.firstWhere((r) => r.item.name == 'OBJ_ROTO').isError,
          isTrue,
        );
        expect(
          finals.firstWhere((r) => r.item.name == 'OBJ_OK').isSuccess,
          isTrue,
        );
      },
    );

    test('continúa con el resto de la cola aunque un elemento falle', () async {
      final dynamicAdapter = _FakeDynamicAdapter(
        failWhen: (cd, target) => cd == 'DR_FAIL',
      );
      final service = BatchTransferService(dynamicAdapter: dynamicAdapter);

      final failing = Procedimiento(
        cdProcedimiento: 'DR_FAIL',
        deTexto: 'BEGIN NULL; END;',
        inConfiguracion: 'REGLA',
        version: 1,
        stProcedimiento: '1',
      );

      final results = <BatchTransferResult>[];
      await service.run(
        items: [_dynamicItem(failing), _dynamicItem()],
        sourceAmbiente: 'Desa',
        targetAmbientes: ['QA'],
        cdUsuario: 'USER1',
        onResult: results.add,
      );

      final finals = results.where((r) => !r.isRunning).toList();
      expect(finals, hasLength(2));
      expect(finals[0].isError, isTrue);
      expect(finals[0].message, contains('ORA-00001'));
      expect(finals[1].isSuccess, isTrue);
    });

    test(
      'procesa cada destino para un mismo elemento y aísla errores por destino',
      () async {
        final dynamicAdapter = _FakeDynamicAdapter(
          failWhen: (cd, target) => target == 'Prod',
        );
        final service = BatchTransferService(dynamicAdapter: dynamicAdapter);

        final results = <BatchTransferResult>[];
        await service.run(
          items: [_dynamicItem()],
          sourceAmbiente: 'Desa',
          targetAmbientes: ['QA', 'Prod'],
          cdUsuario: 'USER1',
          onResult: results.add,
        );

        final finals = results.where((r) => !r.isRunning).toList();
        expect(finals, hasLength(2));
        expect(
          finals.firstWhere((r) => r.targetAmbiente == 'QA').isSuccess,
          isTrue,
        );
        expect(
          finals.firstWhere((r) => r.targetAmbiente == 'Prod').isError,
          isTrue,
        );
      },
    );

    test('excluye tablas sin llamar al adaptador de esquema', () async {
      final schemaAdapter = _FakeSchemaAdapter();
      final service = BatchTransferService(schemaAdapter: schemaAdapter);

      final results = <BatchTransferResult>[];
      await service.run(
        items: [_schemaItem('MI_TABLA', type: 'TABLE')],
        sourceAmbiente: 'Desa',
        targetAmbientes: ['QA'],
        cdUsuario: 'USER1',
        onResult: results.add,
      );

      expect(schemaAdapter.calls, isEmpty);
      final finalResult = results.firstWhere((r) => !r.isRunning);
      expect(finalResult.isError, isTrue);
      expect(finalResult.message, contains('tablas'));
    });

    test(
      'detiene la ejecución al cancelar sin procesar lo pendiente',
      () async {
        final dynamicAdapter = _FakeDynamicAdapter();
        final service = BatchTransferService(dynamicAdapter: dynamicAdapter);
        var cancelled = false;

        final results = <BatchTransferResult>[];
        var processed = 0;
        await service.run(
          items: [_dynamicItem(), _dynamicItem()],
          sourceAmbiente: 'Desa',
          targetAmbientes: ['QA'],
          cdUsuario: 'USER1',
          onResult: (r) {
            results.add(r);
            if (!r.isRunning) {
              processed++;
              if (processed == 1) cancelled = true;
            }
          },
          isCancelled: () => cancelled,
        );

        expect(dynamicAdapter.calls, hasLength(1));
      },
    );

    test('runPairs reintenta solo los pares especificados', () async {
      final dynamicAdapter = _FakeDynamicAdapter();
      final schemaAdapter = _FakeSchemaAdapter();
      final service = BatchTransferService(
        dynamicAdapter: dynamicAdapter,
        schemaAdapter: schemaAdapter,
      );

      final proc1 = _dynamicItem(
        const Procedimiento(
          cdProcedimiento: 'PR_1',
          deTexto: 'BEGIN NULL; END;',
          inConfiguracion: 'R',
          version: 1,
          stProcedimiento: '1',
        ),
      );
      final schema1 = _schemaItem('VIEW_1', type: 'VIEW');

      final pairs = [
        (item: proc1, targetAmbiente: 'QA'),
        (item: schema1, targetAmbiente: 'Prod'),
      ];

      final results = <BatchTransferResult>[];
      await service.runPairs(
        pairs: pairs,
        sourceAmbiente: 'Desa',
        cdUsuario: 'USER_RETRY',
        onResult: results.add,
      );

      final finals = results.where((r) => !r.isRunning).toList();
      expect(finals, hasLength(2));
      expect(dynamicAdapter.calls, ['PR_1->QA']);
      expect(schemaAdapter.calls, ['VIEW_1->Prod']);
    });
  });
}
