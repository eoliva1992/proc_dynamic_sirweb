import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';

/// Estado de la conexión con el backend, de mejor a peor.
enum ServerConnectionState {
  /// Estableciendo la conexión inicial.
  connecting,

  /// Hay comunicación con el servidor.
  online,

  /// Se perdió la conexión y se está reintentando (SignalR reconnect).
  reconnecting,

  /// Sin comunicación con el servidor.
  offline,
}

extension ServerConnectionStateX on ServerConnectionState {
  bool get isOnline => this == ServerConnectionState.online;
  bool get isTransitional =>
      this == ServerConnectionState.connecting ||
      this == ServerConnectionState.reconnecting;

  String get label => switch (this) {
    ServerConnectionState.connecting => 'Conectando…',
    ServerConnectionState.online => 'En línea',
    ServerConnectionState.reconnecting => 'Reconectando…',
    ServerConnectionState.offline => 'Sin conexión',
  };
}

/// Monitorea la disponibilidad del backend y expone un estado observable
/// para la UI.
///
/// Combina tres fuentes de información, de más a menos inmediata:
///
/// 1. **SignalR** (`withAutomaticReconnect`): detecta la caída del servidor al
///    instante mediante los callbacks del hub. Es opcional: si el hub no está
///    disponible el servicio sigue funcionando con las otras dos fuentes.
/// 2. **Resultado real de cada request HTTP**: `SirwebService.guardRequest`
///    informa cada éxito o fallo de red. Es la fuente de verdad, porque refleja
///    exactamente lo que la app está pudiendo hacer.
/// 3. **Heartbeat periódico**: sondea el servidor para detectar tanto la caída
///    mientras la app está ociosa como la recuperación del servicio.
class ConnectionStatusService {
  ConnectionStatusService._();

  static final ConnectionStatusService instance = ConnectionStatusService._();

  /// Host del backend. Debe coincidir con el usado por los demás servicios.
  static const String host = 'http://localhost:5179';

  /// Ruta del hub SignalR. Ajustar si el servidor la expone con otro nombre.
  static const String hubPath = '/hubs/sirweb';

  /// Frecuencia del heartbeat cuando la conexión está sana.
  static const Duration _idleInterval = Duration(seconds: 30);

  /// Frecuencia del heartbeat cuando se perdió la conexión (reintento rápido).
  static const Duration _retryInterval = Duration(seconds: 5);

  /// Estado actual de la conexión, para escuchar desde la UI.
  final ValueNotifier<ServerConnectionState> state =
      ValueNotifier<ServerConnectionState>(ServerConnectionState.connecting);

  /// Momento del último contacto exitoso con el servidor.
  final ValueNotifier<DateTime?> lastOnline = ValueNotifier<DateTime?>(null);

  final http.Client _client = http.Client();
  HubConnection? _hub;
  Timer? _heartbeat;
  bool _started = false;
  bool _checking = false;
  bool _signalrAvailable = false;

  /// `true` si el transporte SignalR está activo (caída detectada al instante).
  bool get signalrAvailable => _signalrAvailable;

  /// Arranca el monitoreo. Es idempotente.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _scheduleHeartbeat();
    unawaited(checkNow());
    unawaited(_connectHub());
  }

  // ── SignalR ────────────────────────────────────────────────────────────────

  Future<void> _connectHub() async {
    try {
      final hub = HubConnectionBuilder()
          .withUrl('$host$hubPath')
          .withAutomaticReconnect()
          .build();

      hub.onclose(({Exception? error}) {
        _signalrAvailable = false;
        // No marcamos offline directamente: dejamos que el heartbeat confirme,
        // así una caída del hub no reporta un falso "sin conexión" si la API
        // REST sigue respondiendo.
        unawaited(checkNow());
      });

      hub.onreconnecting(({Exception? error}) {
        if (state.value.isOnline) _set(ServerConnectionState.reconnecting);
      });

      hub.onreconnected(({String? connectionId}) {
        _signalrAvailable = true;
        _set(ServerConnectionState.online);
      });

      await hub.start();
      _hub = hub;
      _signalrAvailable = true;
      _set(ServerConnectionState.online);
    } catch (_) {
      // El hub puede no existir o tener otra ruta: degradamos silenciosamente
      // al heartbeat HTTP, que cubre igual el caso de uso del indicador.
      _signalrAvailable = false;
    }
  }

  // ── Reportes desde las llamadas HTTP ───────────────────────────────────────

  /// Informa que una llamada al backend respondió correctamente.
  void reportSuccess() {
    lastOnline.value = DateTime.now();
    _set(ServerConnectionState.online);
  }

  /// Informa que una llamada al backend falló por red o timeout.
  void reportFailure() {
    _set(ServerConnectionState.offline);
    // Acelerar el sondeo para detectar la recuperación cuanto antes.
    _scheduleHeartbeat();
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    final interval = state.value.isOnline ? _idleInterval : _retryInterval;
    _heartbeat = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  /// Sondea el servidor una vez y actualiza el estado.
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      // Cualquier respuesta HTTP —incluso 404— prueba que el servidor está
      // levantado y aceptando conexiones. Solo interesa distinguir "responde"
      // de "no responde".
      await _client.get(Uri.parse(host)).timeout(const Duration(seconds: 5));
      reportSuccess();
    } catch (_) {
      _set(ServerConnectionState.offline);
    } finally {
      _checking = false;
    }
  }

  void _set(ServerConnectionState value) {
    if (state.value == value) return;
    final wasOnline = state.value.isOnline;
    state.value = value;
    if (value.isOnline) lastOnline.value = DateTime.now();
    // Cambió la salud de la conexión → ajustar la frecuencia del sondeo.
    if (wasOnline != value.isOnline) _scheduleHeartbeat();
  }

  void dispose() {
    _heartbeat?.cancel();
    _hub?.stop();
    _client.close();
    state.dispose();
    lastOnline.dispose();
  }
}
