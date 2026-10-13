import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';
import '../models/app_notification.dart';
import '../widgets/app_toast.dart';
import 'app_log.dart';
import 'server_config_service.dart';

/// Servicio centralizado de notificaciones.
///
/// Gestiona la persistencia e historial vía endpoints REST (`/tools/notificaciones`),
/// y mantiene la recepción en tiempo real vía SignalR (`/hubs/notifications`).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String hubPath = '/hubs/notifications';
  static const String apiBasePath = '/tools/notificaciones';

  // Shared http client
  static final http.Client _httpClient = http.Client();

  HubConnection? _hub;
  String? _currentUser;
  bool _started = false;

  /// Lista observable de notificaciones recibidas (más recientes primero).
  final ValueNotifier<List<AppNotification>> notifications =
      ValueNotifier<List<AppNotification>>([]);

  /// Conteo de notificaciones no leídas.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Estado de carga para sincronización REST
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  /// Información de la última página obtenida
  NotificationPageResponse? lastPage;

  /// Callback opcional para abrir notas desde un toast o popover
  void Function(String noteId)? onOpenNoteRequested;

  String? get currentUser => _currentUser;

  /// Inicia el servicio y conecta al hub con el usuario dado.
  Future<void> start({required String user}) async {
    if (user.trim().isEmpty) return;
    _currentUser = user.trim();

    // Cargar historial persistido del usuario
    unawaited(fetchNotifications(grupo: _currentUser));

    if (_started && _hub?.state == HubConnectionState.Connected) {
      // Re-suscribir si cambió el usuario
      unawaited(_subscribeUser());
      return;
    }
    _started = true;
    await _connectHub();
  }

  /// Actualiza el usuario activo (por ejemplo si cambia en el diálogo de usuario).
  void updateUser(String user) {
    final trimmed = user.trim();
    if (trimmed.isEmpty || trimmed == _currentUser) return;
    _currentUser = trimmed;
    notifications.value = [];
    _updateUnreadCount();
    unawaited(fetchNotifications(grupo: _currentUser));
    if (_hub?.state == HubConnectionState.Connected) {
      unawaited(_subscribeUser());
    }
  }

  Future<void> _connectHub() async {
    try {
      final baseUrl = await ServerConfigService().getBaseUrl();
      final hub = HubConnectionBuilder()
          .withUrl('$baseUrl$hubPath')
          .withAutomaticReconnect()
          .build();

      hub.onclose(({Exception? error}) {
        AppLog.instance.warning(
          'SignalR Notificaciones cerrado: ${error?.toString() ?? "normal"}',
        );
      });

      hub.onreconnected(({String? connectionId}) {
        AppLog.instance.info(
          'SignalR Notificaciones reconectado ($connectionId)',
        );
        unawaited(_subscribeUser());
      });

      // Escuchar eventos entrantes
      hub.on('notify', _handleIncomingNotification);
      hub.on('notification', _handleIncomingNotification);
      hub.on('Notify', _handleIncomingNotification);

      await hub.start();
      _hub = hub;
      AppLog.instance.info('SignalR Notificaciones conectado con éxito');
      await _subscribeUser();
    } catch (e) {
      AppLog.instance.warning(
        'No se pudo conectar a SignalR Notificaciones ($hubPath): $e',
      );
    }
  }

  Future<void> _subscribeUser() async {
    if (_hub == null || _hub!.state != HubConnectionState.Connected) return;
    if (_currentUser == null || _currentUser!.isEmpty) return;

    try {
      final user = _currentUser!;
      await _hub!.invoke('Subscribe', args: <Object>[user]);
      AppLog.instance.info(
        'Suscrito a notificaciones para usuario: $_currentUser',
      );
    } catch (e) {
      // Si el hub no tiene método Subscribe explícito, ignora silenciosamente
      AppLog.instance.info('Invocación Subscribe omitida o fallida: $e');
    }
  }

  void _handleIncomingNotification(List<dynamic>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    final first = arguments.first;

    AppNotification? notification;
    if (first is Map<String, dynamic>) {
      notification = AppNotification.fromJson(first);
    } else if (first is Map) {
      notification = AppNotification.fromJson(Map<String, dynamic>.from(first));
    } else if (first is String) {
      try {
        final decoded = jsonDecode(first);
        if (decoded is Map<String, dynamic>) {
          notification = AppNotification.fromJson(decoded);
        } else if (decoded is Map) {
          notification = AppNotification.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {
        notification = AppNotification(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'Notificación',
          message: first,
          timestamp: DateTime.now(),
        );
      }
    }

    if (notification != null) {
      addNotification(notification);
    }
  }

  /// Añade una notificación al listado y muestra el toast interactivo.
  void addNotification(AppNotification notif, {bool showToast = true}) {
    final current = List<AppNotification>.from(notifications.value);
    current.insert(0, notif);
    notifications.value = current;
    _updateUnreadCount();

    if (showToast) {
      _showInteractiveToast(notif);
    }
  }

  void _showInteractiveToast(AppNotification notif) {
    final noteId = notif.data?['noteId']?.toString();
    final hasNoteAction =
        noteId != null && noteId.isNotEmpty && onOpenNoteRequested != null;

    if (hasNoteAction) {
      AppToast.infoWithAction(
        notif.message.isNotEmpty ? notif.message : notif.title,
        actionLabel: 'Ver Nota →',
        onAction: () {
          markAsRead(notif.id);
          onOpenNoteRequested?.call(noteId);
        },
      );
    } else {
      switch (notif.kind) {
        case AppNotificationKind.success:
          AppToast.success(
            notif.message.isNotEmpty ? notif.message : notif.title,
          );
          break;
        case AppNotificationKind.warning:
          AppToast.warning(
            notif.message.isNotEmpty ? notif.message : notif.title,
          );
          break;
        case AppNotificationKind.error:
          AppToast.error(
            notif.message.isNotEmpty ? notif.message : notif.title,
          );
          break;
        case AppNotificationKind.info:
          AppToast.info(notif.message.isNotEmpty ? notif.message : notif.title);
          break;
      }
    }
  }

  // ==========================================
  // Métodos REST para persistencia y sincronización
  // ==========================================

  /// Consulta el listado paginado de notificaciones desde el backend REST.
  /// Si [append] es true, añade los items al final sin resetear los existentes.
  Future<NotificationPageResponse?> fetchNotifications({
    int top = 50,
    int pagina = 1,
    bool soloNoLeidas = false,
    String? grupo,
    bool append = false,
  }) async {
    final effectiveGrupo = grupo ?? _currentUser ?? '';
    isLoading.value = true;
    try {
      final baseUrl = await ServerConfigService().getBaseUrl();
      final uri = Uri.parse('$baseUrl$apiBasePath').replace(
        queryParameters: {
          'grupo': effectiveGrupo,
          'soloNoLeidas': soloNoLeidas.toString(),
          'top': top.toString(),
          'pagina': pagina.toString(),
        },
      );

      final response = await _httpClient.get(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> &&
            decoded['data'] is Map<String, dynamic>) {
          final page = NotificationPageResponse.fromJson(
            decoded['data'] as Map<String, dynamic>,
          );
          lastPage = page;

          if (append) {
            // Unir sin duplicar IDs
            final existingIds = notifications.value.map((e) => e.id).toSet();
            final merged = List<AppNotification>.from(notifications.value);
            for (final item in page.items) {
              if (!existingIds.contains(item.id)) {
                merged.add(item);
                existingIds.add(item.id);
              }
            }
            notifications.value = merged;
          } else {
            // Reemplazo o merge conservando posibles notificaciones en vivo que no están en el backend aún
            final serverIds = page.items.map((e) => e.id).toSet();
            final localOnly = notifications.value
                .where((n) => !serverIds.contains(n.id))
                .toList();
            notifications.value = [...localOnly, ...page.items];
          }
          _updateUnreadCount();
          return page;
        }
      } else {
        AppLog.instance.warning(
          'Error HTTP ${response.statusCode} al consultar notificaciones: ${response.body}',
        );
      }
    } catch (e) {
      AppLog.instance.warning('Excepción al consultar notificaciones REST: $e');
    } finally {
      isLoading.value = false;
    }
    return null;
  }

  /// Consulta el detalle de una notificación por ID vía REST.
  Future<AppNotification?> fetchNotificationById(
    String id, {
    String? grupo,
  }) async {
    final effectiveGrupo = grupo ?? _currentUser ?? '';
    try {
      final baseUrl = await ServerConfigService().getBaseUrl();
      final uri = Uri.parse(
        '$baseUrl$apiBasePath/$id',
      ).replace(queryParameters: {'grupo': effectiveGrupo});

      final response = await _httpClient.get(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> &&
            decoded['data'] is Map<String, dynamic>) {
          return AppNotification.fromJson(
            decoded['data'] as Map<String, dynamic>,
          );
        }
      }
    } catch (e) {
      AppLog.instance.warning('Error al consultar notificación $id: $e');
    }
    return null;
  }

  /// Marca una notificación como leída tanto localmente como en el backend.
  Future<void> markAsRead(String id, {String? grupo}) async {
    // Actualización optimista local
    final current = notifications.value;
    final updated = current.map((n) {
      if (n.id == id) {
        return n.copyWith(read: true, readAt: DateTime.now());
      }
      return n;
    }).toList();
    notifications.value = updated;
    _updateUnreadCount();

    // Sincronización REST
    final effectiveGrupo = grupo ?? _currentUser ?? '';
    try {
      final baseUrl = await ServerConfigService().getBaseUrl();
      final uri = Uri.parse(
        '$baseUrl$apiBasePath/$id/marcar-leida',
      ).replace(queryParameters: {'grupo': effectiveGrupo});
      final response = await _httpClient.post(uri);
      if (response.statusCode != 200) {
        AppLog.instance.warning(
          'Respuesta no exitosa al marcar como leída $id: ${response.statusCode}',
        );
      }
    } catch (e) {
      AppLog.instance.warning(
        'Fallo al marcar notificación como leída en backend: $e',
      );
    }
  }

  /// Marca todas las notificaciones como leídas tanto localmente como en el backend.
  Future<void> markAllAsRead({String? grupo}) async {
    // Actualización optimista local
    final current = notifications.value;
    final now = DateTime.now();
    final updated = current
        .map((n) => n.copyWith(read: true, readAt: now))
        .toList();
    notifications.value = updated;
    _updateUnreadCount();

    // Sincronización REST
    final effectiveGrupo = grupo ?? _currentUser ?? '';
    try {
      final baseUrl = await ServerConfigService().getBaseUrl();
      final uri = Uri.parse(
        '$baseUrl$apiBasePath/marcar-todas-leidas',
      ).replace(queryParameters: {'grupo': effectiveGrupo});
      final response = await _httpClient.post(uri);
      if (response.statusCode != 200) {
        AppLog.instance.warning(
          'Respuesta no exitosa al marcar todas leídas: ${response.statusCode}',
        );
      }
    } catch (e) {
      AppLog.instance.warning(
        'Fallo al marcar todas como leídas en backend: $e',
      );
    }
  }

  /// Elimina una notificación por ID tanto localmente como en el backend.
  Future<bool> deleteNotification(String id, {String? grupo}) async {
    // Actualización optimista local
    final previous = notifications.value;
    notifications.value = previous.where((n) => n.id != id).toList();
    _updateUnreadCount();

    // Sincronización REST
    final effectiveGrupo = grupo ?? _currentUser ?? '';
    try {
      final baseUrl = await ServerConfigService().getBaseUrl();
      final uri = Uri.parse(
        '$baseUrl$apiBasePath/$id',
      ).replace(queryParameters: {'grupo': effectiveGrupo});
      final response = await _httpClient.delete(uri);
      if (response.statusCode == 200) {
        return true;
      } else {
        AppLog.instance.warning(
          'Respuesta no exitosa al eliminar notificación $id: ${response.statusCode}',
        );
        // Rollback opcional si fuera necesario
        return false;
      }
    } catch (e) {
      AppLog.instance.warning('Fallo al eliminar notificación en backend: $e');
      return false;
    }
  }

  /// Limpia todo el historial de notificaciones en memoria.
  void clearAll() {
    notifications.value = [];
    _updateUnreadCount();
  }

  void _updateUnreadCount() {
    unreadCount.value = notifications.value.where((n) => !n.read).length;
  }
}
