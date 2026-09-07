import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../services/connection_status_service.dart';
import 'app_toast.dart';

/// Alerta global de pérdida de conexión con el servidor.
///
/// Combina dos avisos complementarios:
///  - Una **franja fija** bajo la barra superior, visible mientras dure el
///    problema (no se puede pasar por alto ni se descarta sola).
///  - Un **toast persistente** al momento de la caída y otro de confirmación
///    al recuperarse, para notificar el cambio aunque la franja no se mire.
///
/// Se coloca envolviendo el contenido principal de la pantalla.
class ConnectionAlert extends StatefulWidget {
  const ConnectionAlert({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectionAlert> createState() => _ConnectionAlertState();
}

class _ConnectionAlertState extends State<ConnectionAlert> {
  ToastificationItem? _offlineToast;
  bool _estuvoOffline = false;

  @override
  void initState() {
    super.initState();
    ConnectionStatusService.instance.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    ConnectionStatusService.instance.state.removeListener(_onStateChanged);
    _cerrarToast();
    super.dispose();
  }

  void _cerrarToast() {
    final toast = _offlineToast;
    if (toast != null) {
      AppToast.dismiss(toast);
      _offlineToast = null;
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = ConnectionStatusService.instance.state.value;

    if (state == ServerConnectionState.offline) {
      // Un único toast por episodio de caída: si ya hay uno visible no se
      // apila otro en cada reintento fallido del heartbeat.
      if (_offlineToast == null) {
        _offlineToast = AppToast.persistentError(
          'Se perdió la conexión con el servidor',
          detail:
              'Los cambios no se pueden guardar hasta que se restablezca. '
              'Se está reintentando automáticamente.',
          actionLabel: 'Reintentar ahora',
          onAction: () => ConnectionStatusService.instance.checkNow(),
        );
      }
      _estuvoOffline = true;
    } else if (state.isOnline) {
      _cerrarToast();
      // Solo confirmamos la recuperación si antes hubo una caída real; así no
      // aparece un toast en el arranque normal de la app.
      if (_estuvoOffline) {
        _estuvoOffline = false;
        AppToast.success('Conexión restablecida');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ServerConnectionState>(
      valueListenable: ConnectionStatusService.instance.state,
      builder: (context, state, child) {
        final mostrar =
            !state.isOnline && state != ServerConnectionState.connecting;
        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: mostrar
                  ? _ConnectionBanner(state: state)
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(child: child!),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.state});

  final ServerConnectionState state;

  @override
  Widget build(BuildContext context) {
    final reconectando = state == ServerConnectionState.reconnecting;
    final color = reconectando
        ? const Color(0xFFF39C12)
        : const Color(0xFFE74C3C);

    return Material(
      color: color.withValues(alpha: 0.12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: color, width: 1.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: reconectando
                  ? CircularProgressIndicator(strokeWidth: 2, color: color)
                  : Icon(Icons.cloud_off_rounded, size: 15, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                reconectando
                    ? 'Reconectando con el servidor…'
                    : 'Sin conexión con el servidor — los cambios no se '
                          'pueden guardar. Reintentando automáticamente…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => ConnectionStatusService.instance.checkNow(),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text(
                'Reintentar',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
