import '../models/batch_transfer_result.dart';
import '../models/bulk_backup_item.dart';
import 'app_log.dart';
import 'schema_service.dart';
import 'transfer_service.dart';

/// Resultado de intentar transferir un objeto Oracle no-tabla (crear/actualizar
/// vía `CREATE OR REPLACE` + GRANTs/sinónimos opcionales).
typedef SchemaTransferOutcome = ({bool success, String message});

/// Adaptador para transferir procedimientos dinámicos entre ambientes.
/// Aislado detrás de una interfaz para poder inyectar un doble en tests.
abstract class DynamicProcedureTransferAdapter {
  Future<TransferResult> transfer({
    required String cdProcedimiento,
    required String sourceCode,
    required String inConfiguracion,
    required String cdUsuario,
    required String targetAmbiente,
  });
}

class SirwebDynamicProcedureTransferAdapter
    implements DynamicProcedureTransferAdapter {
  const SirwebDynamicProcedureTransferAdapter();

  @override
  Future<TransferResult> transfer({
    required String cdProcedimiento,
    required String sourceCode,
    required String inConfiguracion,
    required String cdUsuario,
    required String targetAmbiente,
  }) => TransferService.transfer(
    cdProcedimiento: cdProcedimiento,
    sourceCode: sourceCode,
    inConfiguracion: inConfiguracion,
    cdUsuario: cdUsuario,
    targetAmbiente: targetAmbiente,
  );
}

/// Adaptador para transferir objetos Oracle (PROCEDURE, PACKAGE, FUNCTION,
/// TYPE, VIEW). Las tablas quedan fuera de alcance: no admiten
/// `CREATE OR REPLACE`.
abstract class SchemaObjectTransferAdapter {
  Future<SchemaTransferOutcome> transfer({
    required BulkBackupItem item,
    required String sourceAmbiente,
    required String targetAmbiente,
    required bool transferGrants,
    required bool transferSynonyms,
  });
}

class SchemaServiceTransferAdapter implements SchemaObjectTransferAdapter {
  const SchemaServiceTransferAdapter();

  @override
  Future<SchemaTransferOutcome> transfer({
    required BulkBackupItem item,
    required String sourceAmbiente,
    required String targetAmbiente,
    required bool transferGrants,
    required bool transferSynonyms,
  }) async {
    final svc = SchemaService.instance;
    final objectType = item.type.toUpperCase();
    final isPackage = objectType == 'PACKAGE';

    final source = await svc.getObjectSource(
      item.name,
      objectType,
      ambiente: sourceAmbiente,
    );

    final errores =
        <({int line, int position, String text, String attribute})>[];
    if (isPackage) {
      if (source.spec.trim().isNotEmpty) {
        errores.addAll(
          await svc.compileObject(
            source.spec,
            item.name,
            'PACKAGE',
            ambiente: targetAmbiente,
          ),
        );
      }
      final body = source.body ?? '';
      if (errores.isEmpty && body.trim().isNotEmpty) {
        errores.addAll(
          await svc.compileObject(
            body,
            item.name,
            'PACKAGE BODY',
            ambiente: targetAmbiente,
          ),
        );
      }
    } else {
      final texto = source.spec;
      if (texto.trim().isEmpty) {
        return (success: false, message: 'No hay fuente para transferir.');
      }
      errores.addAll(
        await svc.compileObject(
          texto,
          item.name,
          objectType,
          ambiente: targetAmbiente,
        ),
      );
    }

    AppLog.instance.compilation(
      objectName: item.name,
      objectType: objectType,
      ambiente: targetAmbiente,
      errors: errores,
      source: 'Transferencia',
    );
    if (errores.isNotEmpty) {
      final primero = errores.first;
      return (
        success: false,
        message:
            '${primero.attribute} línea ${primero.line}, col ${primero.position}: '
            '${primero.text.trim()}',
      );
    }

    if (!transferGrants && !transferSynonyms) {
      return (success: true, message: 'Creado/actualizado en $targetAmbiente');
    }

    var owner = await _resolveOwner(item.name, objectType, targetAmbiente);
    if (owner.isEmpty) {
      owner = await _resolveOwner(item.name, objectType, sourceAmbiente);
    }
    final qualified = owner.isEmpty ? item.name : '$owner.${item.name}';

    final fallos = <String>[];
    var grantsOk = 0;
    var synonymsOk = 0;

    Future<void> run(String ddl) async {
      try {
        await svc.executeDdl(
          ddl,
          objectName: item.name,
          objectType: objectType,
          ambiente: targetAmbiente,
        );
        AppLog.instance.ddl(
          ddl,
          ambiente: targetAmbiente,
          source: 'Transferencia',
        );
      } catch (e) {
        final msg = AppLog.describe(e);
        AppLog.instance.ddl(
          ddl,
          ambiente: targetAmbiente,
          errorMessage: msg,
          source: 'Transferencia',
        );
        fallos.add('$ddl → $msg');
      }
    }

    if (transferGrants) {
      final privs = await svc.getObjectPrivileges(
        item.name,
        ambiente: sourceAmbiente,
      );
      for (final p in privs) {
        if (p.privilege.isEmpty || p.grantee.isEmpty) continue;
        final ddl =
            'GRANT ${p.privilege} ON $qualified TO ${p.grantee}'
            '${p.grantable ? ' WITH GRANT OPTION' : ''}';
        final antes = fallos.length;
        await run(ddl);
        if (fallos.length == antes) grantsOk++;
      }
    }

    if (transferSynonyms) {
      final syns = await svc.getSynonyms(item.name, ambiente: sourceAmbiente);
      for (final s in syns) {
        if (s.synonymName.isEmpty) continue;
        final nombre = s.isPublic || s.owner.isEmpty || s.owner == 'PUBLIC'
            ? s.synonymName
            : '${s.owner}.${s.synonymName}';
        final ddl =
            'CREATE OR REPLACE ${s.isPublic ? 'PUBLIC ' : ''}'
            'SYNONYM $nombre FOR $qualified';
        final antes = fallos.length;
        await run(ddl);
        if (fallos.length == antes) synonymsOk++;
      }
    }

    final resumen = StringBuffer('Creado/actualizado en $targetAmbiente');
    if (grantsOk > 0) resumen.write(' · $grantsOk grant(s)');
    if (synonymsOk > 0) resumen.write(' · $synonymsOk sinónimo(s)');
    if (fallos.isNotEmpty) {
      resumen.write(' · ${fallos.length} sentencia(s) con error');
    }
    return (success: true, message: resumen.toString());
  }

  Future<String> _resolveOwner(
    String objectName,
    String objectType,
    String ambiente,
  ) async {
    try {
      final info = await SchemaService.instance.getObjectInfo(
        objectName,
        objectType,
        ambiente: ambiente,
      );
      for (final e in info) {
        if (e.name.toUpperCase() == 'OWNER') return e.value.toUpperCase();
      }
    } catch (_) {
      /* se ignora: el DDL se emite sin calificar el esquema */
    }
    return '';
  }
}

typedef BatchTransferResultCallback = void Function(BatchTransferResult result);

/// Orquesta la transferencia de una selección mixta (reglas de negocio +
/// objetos Oracle reemplazables) desde un ambiente origen hacia uno o varios
/// destinos. Ejecuta elemento×destino en forma secuencial; un fallo no
/// detiene el resto de la cola.
class BatchTransferService {
  BatchTransferService({
    DynamicProcedureTransferAdapter? dynamicAdapter,
    SchemaObjectTransferAdapter? schemaAdapter,
  }) : _dynamicAdapter =
           dynamicAdapter ?? const SirwebDynamicProcedureTransferAdapter(),
       _schemaAdapter = schemaAdapter ?? const SchemaServiceTransferAdapter();

  final DynamicProcedureTransferAdapter _dynamicAdapter;
  final SchemaObjectTransferAdapter _schemaAdapter;

  static bool _neverCancelled() => false;

  Future<void> run({
    required List<BulkBackupItem> items,
    required String sourceAmbiente,
    required List<String> targetAmbientes,
    required String cdUsuario,
    bool transferGrants = false,
    bool transferSynonyms = false,
    required BatchTransferResultCallback onResult,
    bool Function() isCancelled = _neverCancelled,
  }) async {
    final pairs = [
      for (final item in items)
        for (final target in targetAmbientes)
          (item: item, targetAmbiente: target),
    ];
    await runPairs(
      pairs: pairs,
      sourceAmbiente: sourceAmbiente,
      cdUsuario: cdUsuario,
      transferGrants: transferGrants,
      transferSynonyms: transferSynonyms,
      onResult: onResult,
      isCancelled: isCancelled,
    );
  }

  Future<void> runPairs({
    required List<({BulkBackupItem item, String targetAmbiente})> pairs,
    required String sourceAmbiente,
    required String cdUsuario,
    bool transferGrants = false,
    bool transferSynonyms = false,
    required BatchTransferResultCallback onResult,
    bool Function() isCancelled = _neverCancelled,
  }) async {
    for (final pair in pairs) {
      if (isCancelled()) return;
      onResult(
        BatchTransferResult(
          item: pair.item,
          targetAmbiente: pair.targetAmbiente,
          status: BatchTransferStatus.running,
        ),
      );
      final result = await _transferOne(
        item: pair.item,
        sourceAmbiente: sourceAmbiente,
        targetAmbiente: pair.targetAmbiente,
        cdUsuario: cdUsuario,
        transferGrants: transferGrants,
        transferSynonyms: transferSynonyms,
      );
      onResult(result);
    }
  }

  Future<BatchTransferResult> _transferOne({
    required BulkBackupItem item,
    required String sourceAmbiente,
    required String targetAmbiente,
    required String cdUsuario,
    required bool transferGrants,
    required bool transferSynonyms,
  }) async {
    AppLog.instance.info(
      'Transferencia por lote ${item.name}: $sourceAmbiente → $targetAmbiente',
      source: 'Transferencia',
    );
    try {
      if (item.source == BulkBackupSource.dynamicProcedure) {
        final proc = item.procedimiento;
        if (proc == null) {
          return BatchTransferResult(
            item: item,
            targetAmbiente: targetAmbiente,
            status: BatchTransferStatus.error,
            message: 'Falta el texto fuente del procedimiento',
          );
        }
        final result = await _dynamicAdapter.transfer(
          cdProcedimiento: proc.cdProcedimiento,
          sourceCode: proc.deTexto,
          inConfiguracion: proc.inConfiguracion,
          cdUsuario: cdUsuario,
          targetAmbiente: targetAmbiente,
        );
        return BatchTransferResult(
          item: item,
          targetAmbiente: targetAmbiente,
          status: result.success
              ? BatchTransferStatus.success
              : BatchTransferStatus.error,
          message: result.message,
        );
      }

      if (item.type.toUpperCase() == 'TABLE') {
        return BatchTransferResult(
          item: item,
          targetAmbiente: targetAmbiente,
          status: BatchTransferStatus.error,
          message:
              'Las tablas no son compatibles con la transferencia por lote',
        );
      }

      final outcome = await _schemaAdapter.transfer(
        item: item,
        sourceAmbiente: sourceAmbiente,
        targetAmbiente: targetAmbiente,
        transferGrants: transferGrants,
        transferSynonyms: transferSynonyms,
      );
      return BatchTransferResult(
        item: item,
        targetAmbiente: targetAmbiente,
        status: outcome.success
            ? BatchTransferStatus.success
            : BatchTransferStatus.error,
        message: outcome.message,
      );
    } catch (e, st) {
      AppLog.instance.exception(
        'Transferencia por lote ${item.name} a $targetAmbiente',
        e,
        stack: st,
        source: 'Transferencia',
      );
      return BatchTransferResult(
        item: item,
        targetAmbiente: targetAmbiente,
        status: BatchTransferStatus.error,
        message: AppLog.describe(e),
      );
    }
  }
}
