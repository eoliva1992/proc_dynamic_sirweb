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
      return (
        success: true,
        message: exists
            ? 'Actualizado en $targetAmbiente correctamente'
            : 'Creado en $targetAmbiente correctamente',
      );
    } catch (e) {
      return (
        success: false,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}
