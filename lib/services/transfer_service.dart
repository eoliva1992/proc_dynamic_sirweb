import '../services/app_log.dart';
import '../services/sirweb_service.dart';

typedef TransferResult = ({bool success, String message});

abstract final class TransferService {
  static Future<TransferResult> transfer({
    required String cdProcedimiento,
    required String sourceCode,
    required String inConfiguracion,
    required String cdUsuario,
    required String targetAmbiente,
  }) async {
    final svc = SirwebService();
    AppLog.instance.transaction(
      'Transferir $cdProcedimiento → $targetAmbiente',
      source: 'Transferencia',
      datos: {
        'Usuario': cdUsuario,
        'Categoria': inConfiguracion,
        'Tamano': '${sourceCode.length} chars',
      },
    );
    try {
      // Check whether the procedure already exists in the target environment
      bool exists = true;
      try {
        await svc.obtenerProcedimiento(
          cdProcedimiento,
          ambiente: targetAmbiente,
        );
      } catch (_) {
        exists = false;
      }

      if (exists) {
        await svc.actualizarProcedimiento(
          cdProcedimiento: cdProcedimiento,
          deTexto: sourceCode,
          cdUsuario: cdUsuario,
          inConfiguracion: inConfiguracion,
          ambiente: targetAmbiente,
        );
      } else {
        await svc.crearProcedimiento(
          cdProcedimiento: cdProcedimiento,
          deTexto: sourceCode,
          inConfiguracion: inConfiguracion,
          cdUsuario: cdUsuario,
          ambiente: targetAmbiente,
        );
      }
      final mensaje = exists
          ? 'Actualizado en $targetAmbiente correctamente'
          : 'Creado en $targetAmbiente correctamente';
      AppLog.instance.success(
        '$cdProcedimiento - $mensaje',
        source: 'Transferencia',
      );
      return (success: true, message: mensaje);
    } catch (e) {
      AppLog.instance.exception(
        'Transferir $cdProcedimiento a $targetAmbiente',
        e,
        source: 'Transferencia',
        datos: {'Usuario': cdUsuario},
      );
      return (
        success: false,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}
