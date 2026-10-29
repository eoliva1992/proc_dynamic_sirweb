import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/oracle_credential.dart';
import 'server_config_service.dart';
import 'sirweb_service.dart';

/// Servicio para consultar y actualizar en caliente las credenciales de conexión
/// Oracle para los distintos ambientes, interactuando con `/tools/oracle-credenciales`.
class OracleCredencialesService {
  OracleCredencialesService._();
  static final OracleCredencialesService instance =
      OracleCredencialesService._();

  static final http.Client _client = http.Client();
  static const Duration _defaultTimeout = Duration(seconds: 15);

  Future<String> _getBaseUrl() async {
    final host = await ServerConfigService().getBaseUrl();
    return '$host/tools/oracle-credenciales';
  }

  /// Consulta el estado actual de las credenciales de Oracle.
  /// Si se especifica [ambiente], devuelve solo el estado de ese ambiente.
  /// Si es null, devuelve la lista de todos los ambientes configurados.
  Future<List<OracleCredentialStatus>> consultarEstado({
    String? ambiente,
  }) async {
    final base = await _getBaseUrl();
    final queryParams = <String, String>{};
    if (ambiente != null && ambiente.trim().isNotEmpty) {
      queryParams['ambiente'] = ambiente.trim();
    }

    final uri = Uri.parse(
      '$base/estado',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    return SirwebService.guardRequest(
      () async {
        final res = await _client
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(_defaultTimeout);

        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (json['success'] != true) {
          throw Exception(
            json['error']?.toString() ??
                json['message']?.toString() ??
                'Error al consultar estado de credenciales Oracle',
          );
        }

        final rawData = json['data'];
        if (rawData is List) {
          return rawData
              .map(
                (e) =>
                    OracleCredentialStatus.fromJson(e as Map<String, dynamic>),
              )
              .toList();
        } else if (rawData is Map<String, dynamic>) {
          return [OracleCredentialStatus.fromJson(rawData)];
        }
        return <OracleCredentialStatus>[];
      },
      timeout: _defaultTimeout,
      contexto: 'OracleCredencialesService.consultarEstado',
    );
  }

  /// Actualiza en caliente el usuario, password, host y puerto de un ambiente Oracle.
  /// La modificación vive en memoria del servidor mientras esté en ejecución.
  Future<void> actualizarCredenciales({
    required String ambiente,
    required String userId,
    required String password,
    required String cdUsuario,
    String? host,
    String? port,
  }) async {
    final base = await _getBaseUrl();
    final uri = Uri.parse(base);

    final payload = <String, dynamic>{
      'ambiente': ambiente,
      'userId': userId,
      'password': password,
      'cdUsuario': cdUsuario,
      if (host != null && host.trim().isNotEmpty) 'host': host.trim(),
      if (port != null && port.trim().isNotEmpty) 'port': port.trim(),
    };

    return SirwebService.guardRequest(
      () async {
        final res = await _client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(_defaultTimeout);

        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (json['success'] != true) {
          throw Exception(
            json['error']?.toString() ??
                json['message']?.toString() ??
                'Error al actualizar credenciales de Oracle',
          );
        }
      },
      timeout: _defaultTimeout,
      contexto: 'OracleCredencialesService.actualizarCredenciales',
    );
  }

  /// Restablece las credenciales del ambiente descartando el override temporal
  /// y volviendo a tomar los valores de la configuración original del backend.
  Future<void> restablecerCredenciales({
    required String ambiente,
    required String cdUsuario,
  }) async {
    final base = await _getBaseUrl();
    final uri = Uri.parse('$base/restablecer');

    final payload = {'ambiente': ambiente, 'cdUsuario': cdUsuario};

    return SirwebService.guardRequest(
      () async {
        final res = await _client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(_defaultTimeout);

        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (json['success'] != true) {
          throw Exception(
            json['error']?.toString() ??
                json['message']?.toString() ??
                'Error al restablecer credenciales de Oracle',
          );
        }
      },
      timeout: _defaultTimeout,
      contexto: 'OracleCredencialesService.restablecerCredenciales',
    );
  }

  /// Consulta el historial paginado de auditoría de cambios de credenciales Oracle.
  Future<OracleCredencialHistorialPagedResult> consultarHistorial({
    String? ambiente,
    int top = 50,
    int pagina = 1,
  }) async {
    final base = await _getBaseUrl();
    final queryParams = <String, String>{
      'top': top.toString(),
      'pagina': pagina.toString(),
    };
    if (ambiente != null && ambiente.trim().isNotEmpty) {
      queryParams['ambiente'] = ambiente.trim();
    }

    final uri = Uri.parse(
      '$base/historial',
    ).replace(queryParameters: queryParams);

    return SirwebService.guardRequest(
      () async {
        final res = await _client
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(_defaultTimeout);

        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (json['success'] != true) {
          throw Exception(
            json['error']?.toString() ??
                json['message']?.toString() ??
                'Error al consultar historial de credenciales Oracle',
          );
        }

        final rawData = json['data'] as Map<String, dynamic>? ?? {};
        return OracleCredencialHistorialPagedResult.fromJson(rawData);
      },
      timeout: _defaultTimeout,
      contexto: 'OracleCredencialesService.consultarHistorial',
    );
  }
}
