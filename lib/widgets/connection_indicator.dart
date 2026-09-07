import 'package:flutter/material.dart';

import '../services/connection_status_service.dart';

/// Indicador compacto del estado de conexión con el servidor.
///
/// Muestra un punto de color —que late mientras se está (re)conectando— y,
/// opcionalmente, la etiqueta de estado. El tooltip detalla el transporte en
/// uso y el momento del último contacto exitoso.
class ConnectionIndicator extends StatefulWidget {
  const ConnectionIndicator({
    super.key,
    this.showLabel = true,
    this.onlineLabelColor,
  });

  /// Si es `false` solo se dibuja el punto (útil en barras muy angostas).
  final bool showLabel;

  /// Color del texto cuando la conexión está sana. Se usa para adaptarse a
  /// fondos oscuros como la AppBar; si es `null` toma el color del tema.
  final Color? onlineLabelColor;

  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse(ConnectionStatusService.instance.state.value);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// El punto solo late mientras la conexión está en transición, para no
  /// distraer con una animación permanente cuando todo está bien.
  void _syncPulse(ServerConnectionState state) {
    if (state.isTransitional) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_pulse.isAnimating) _pulse.stop();
      _pulse.value = 1;
    }
  }

  Color _colorFor(ServerConnectionState state, ColorScheme cs) =>
      switch (state) {
        ServerConnectionState.online => const Color(0xFF27AE60),
        ServerConnectionState.connecting => const Color(0xFFF39C12),
        ServerConnectionState.reconnecting => const Color(0xFFF39C12),
        ServerConnectionState.offline => const Color(0xFFE74C3C),
      };

  String _tooltip(ServerConnectionState state) {
    final svc = ConnectionStatusService.instance;
    final buffer = StringBuffer(state.label);
    if (!state.isOnline) {
      final last = svc.lastOnline.value;
      if (last != null) {
        buffer.write('\nÚltima conexión: ${_hhmmss(last)}');
      }
      buffer.write('\nReintentando automáticamente…');
    } else {
      buffer.write(
        svc.signalrAvailable
            ? '\nSignalR conectado'
            : '\nSondeo periódico (SignalR no disponible)',
      );
    }
    return buffer.toString();
  }

  String _hhmmss(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<ServerConnectionState>(
      valueListenable: ConnectionStatusService.instance.state,
      builder: (context, state, _) {
        _syncPulse(state);
        final color = _colorFor(state, cs);

        return Tooltip(
          message: _tooltip(state),
          preferBelow: false,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            // Permite forzar un reintento inmediato sin esperar al heartbeat.
            onTap: () => ConnectionStatusService.instance.checkNow(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _pulse.drive(Tween<double>(begin: 0.35, end: 1.0)),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(width: 6),
                    Text(
                      state.label,
                      style: TextStyle(
                        color: state.isOnline
                            ? (widget.onlineLabelColor ??
                                  cs.onSurface.withValues(alpha: 0.65))
                            : color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
