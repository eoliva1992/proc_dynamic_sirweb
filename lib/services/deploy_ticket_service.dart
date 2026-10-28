import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/deploy_ticket.dart';
import 'app_log.dart';
import 'server_config_service.dart';
import 'sirweb_service.dart';

/// Respuesta paginada de tickets de despliegue.
typedef DeployTicketPage = ({
  List<DeployTicket> items,
  int pagina,
  int top,
  bool tieneSiguiente,
  bool tienePrevio,
});

/// Servicio cliente para el CRUD de Tickets de Despliegue / Fichas de Pase.
///
/// Endpoints:
///  - GET    /tools/ticket-despliegue?...
///  - GET    /tools/ticket-despliegue/{id}
///  - POST   /tools/ticket-despliegue
///  - PUT    /tools/ticket-despliegue/{id}
///  - DELETE /tools/ticket-despliegue/{id}
class DeployTicketService {
  DeployTicketService._();

  static final instance = DeployTicketService._();

  static final http.Client _client = http.Client();

  /// Usuario del sistema (fallback Windows)
  static String currentUser = (Platform.environment['USERNAME'] ?? '')
      .toUpperCase();

  /// Obtiene la URL base para tickets de despliegue
  static Future<String> getBaseUrl() async {
    final base = await ServerConfigService().getBaseUrl();
    return '$base/tools/ticket-despliegue';
  }

  /// Consulta paginada con filtros opcionales
  Future<DeployTicketPage> search({
    String? tipoSolicitud,
    String? numeroSolicitud,
    String? autoriza,
    String? database,
    String? databaseDestino,
    int top = 50,
    int pagina = 1,
  }) async {
    return SirwebService.guardRequest(() async {
      final base = await getBaseUrl();
      final params = <String, String>{
        'top': top.toString(),
        'pagina': pagina.toString(),
      };

      if (tipoSolicitud != null && tipoSolicitud.trim().isNotEmpty) {
        params['tipoSolicitud'] = tipoSolicitud.trim();
      }
      if (numeroSolicitud != null && numeroSolicitud.trim().isNotEmpty) {
        params['numeroSolicitud'] = numeroSolicitud.trim();
      }
      if (autoriza != null && autoriza.trim().isNotEmpty) {
        params['autoriza'] = autoriza.trim();
      }
      if (database != null && database.trim().isNotEmpty) {
        params['database'] = database.trim();
      }
      if (databaseDestino != null && databaseDestino.trim().isNotEmpty) {
        params['databaseDestino'] = databaseDestino.trim();
      }

      final uri = Uri.parse(base).replace(queryParameters: params);
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar tickets (${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>? ?? {};
      final rawItems = data['items'] as List<dynamic>? ?? [];

      final items = rawItems
          .whereType<Map<String, dynamic>>()
          .map(DeployTicket.fromJson)
          .toList();

      final page = data['pagina'] is int ? data['pagina'] as int : pagina;
      final topVal = data['top'] is int ? data['top'] as int : top;
      final hasNext = data['tieneSiguiente'] == true;
      final hasPrev = data['tienePrevio'] == true;

      return (
        items: items,
        pagina: page,
        top: topVal,
        tieneSiguiente: hasNext,
        tienePrevio: hasPrev,
      );
    }, contexto: 'consulta de tickets de despliegue');
  }

  /// Obtiene un ticket específico por su ID
  Future<DeployTicket> getById(String id) async {
    return SirwebService.guardRequest(() async {
      final base = await getBaseUrl();
      final uri = Uri.parse('$base/$id');
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al obtener ticket ($id): ${response.statusCode} ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['success'] == false || decoded['error'] != null) {
        final err =
            decoded['error'] ?? decoded['message'] ?? 'Error al obtener ticket';
        throw Exception(err.toString());
      }

      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('No se encontraron datos para el ticket $id');
      }

      return DeployTicket.fromJson(data);
    }, contexto: 'obtener ticket $id');
  }

  /// Registra un nuevo ticket de despliegue
  Future<DeployTicket> create(DeployTicket ticket) async {
    return SirwebService.guardRequest(() async {
      final base = await getBaseUrl();
      final uri = Uri.parse(base);
      final bodyJson = jsonEncode(ticket.toJsonForCreate());

      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: bodyJson,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          'Error al crear ticket (${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['success'] == false || decoded['error'] != null) {
        final err =
            decoded['error'] ?? decoded['message'] ?? 'Error al crear ticket';
        throw Exception(err.toString());
      }

      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('La respuesta del servidor no incluyó datos creados');
      }

      final created = DeployTicket.fromJson(data);
      AppLog.instance.info(
        'Ticket creado: ${created.numeroSolicitud} (${created.id})',
        source: 'DeployTicket',
      );
      return created;
    }, contexto: 'crear ticket de despliegue');
  }

  /// Modifica un ticket de despliegue existente
  Future<DeployTicket> update(DeployTicket ticket) async {
    if (ticket.id.isEmpty) {
      throw ArgumentError('No se puede actualizar un ticket sin ID');
    }

    final effectiveUser = (ticket.usuarioActualiza?.trim().isNotEmpty ?? false)
        ? ticket.usuarioActualiza!.trim()
        : currentUser;
    final payloadTicket = ticket.copyWith(usuarioActualiza: effectiveUser);

    return SirwebService.guardRequest(() async {
      final base = await getBaseUrl();
      final uri = Uri.parse('$base/${payloadTicket.id}');
      final bodyJson = jsonEncode(payloadTicket.toJsonForUpdate());

      final response = await _client.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: bodyJson,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al actualizar ticket (${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['success'] == false || decoded['error'] != null) {
        final err =
            decoded['error'] ??
            decoded['message'] ??
            'Error al actualizar ticket';
        throw Exception(err.toString());
      }

      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception(
          'La respuesta del servidor no incluyó datos actualizados',
        );
      }

      final updated = DeployTicket.fromJson(data);
      AppLog.instance.info(
        'Ticket actualizado: ${updated.numeroSolicitud} (${updated.id})',
        source: 'DeployTicket',
      );
      return updated;
    }, contexto: 'actualizar ticket de despliegue');
  }

  /// Guarda un ticket (decide automáticamente entre create y update)
  Future<DeployTicket> save(DeployTicket ticket) async {
    if (ticket.isPersisted) {
      return update(ticket);
    } else {
      return create(ticket);
    }
  }

  /// Elimina un ticket por ID
  Future<bool> delete(String id) async {
    if (id.isEmpty) return false;

    return SirwebService.guardRequest(() async {
      final base = await getBaseUrl();
      final uri = Uri.parse('$base/$id');

      final response = await _client.delete(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
          'Error al eliminar ticket ($id): ${response.statusCode} ${response.body}',
        );
      }

      AppLog.instance.info('Ticket eliminado: $id', source: 'DeployTicket');
      return true;
    }, contexto: 'eliminar ticket de despliegue');
  }
}
