import 'dart:async';
import 'package:flutter/material.dart';
import '../services/schema_service.dart';

/// Indicador flotante animado que muestra el estado de carga del schema Oracle.
///
/// Se coloca en la esquina inferior izquierda de la pantalla con un `Positioned`.
/// Solo es visible durante la carga, refresco o error — se oculta con fade
/// cuando el schema está listo.
///
/// Es auto-contenido: escucha directamente [SchemaService.instance.status]
/// sin necesitar parámetros externos.
class SchemaStatusOverlay extends StatefulWidget {
  const SchemaStatusOverlay({super.key});

  @override
  State<SchemaStatusOverlay> createState() => _SchemaStatusOverlayState();
}

class _SchemaStatusOverlayState extends State<SchemaStatusOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late SchemaLoadStatus _status;

  /// Ensures the overlay stays visible at least [_kMinVisibleMs] milliseconds
  /// even when loading completes almost instantly (e.g. server not reachable).
  Timer? _hideTimer;
  bool _forceVisible = false;
  static const _kMinVisibleMs = 1500;

  @override
  void initState() {
    super.initState();
    _status = SchemaService.instance.status.value;
    SchemaService.instance.status.addListener(_onStatusChanged);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // If already in an active state when mounted, lock visibility immediately.
    if (_isActiveFor(_status)) _startMinTimer();
  }

  /// Locks the overlay visible for [_kMinVisibleMs] ms.
  /// Idempotent: a second call while already locked is ignored.
  void _startMinTimer() {
    if (_forceVisible) return;
    _forceVisible = true;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: _kMinVisibleMs), () {
      if (mounted) setState(() => _forceVisible = false);
    });
  }

  void _onStatusChanged() {
    if (!mounted) return;
    final newStatus = SchemaService.instance.status.value;
    // Capture visibility BEFORE updating _status.
    final wasHidden = !_isActive;

    setState(() => _status = newStatus);

    // When transitioning from hidden to visible, start minimum display timer.
    if (wasHidden && _isActiveFor(newStatus)) {
      _startMinTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SchemaService.instance.status.removeListener(_onStatusChanged);
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool _isActiveFor(SchemaLoadStatus s) =>
      s != SchemaLoadStatus.idle && s != SchemaLoadStatus.ready;

  bool get _isActive => _isActiveFor(_status) || _forceVisible;

  bool get _isSpinning =>
      _status == SchemaLoadStatus.loadingLocal ||
      _status == SchemaLoadStatus.loadingServer ||
      _status == SchemaLoadStatus.refreshing;

  bool get _isError => _status == SchemaLoadStatus.error;

  (IconData, String) get _content => switch (_status) {
        SchemaLoadStatus.idle          => (Icons.dns_outlined, 'Schema no cargado'),
        SchemaLoadStatus.loadingLocal  => (Icons.storage, 'Leyendo schema local...'),
        SchemaLoadStatus.loadingServer => (Icons.cloud_download_outlined, 'Descargando schema del servidor...'),
        SchemaLoadStatus.refreshing    => (Icons.sync, 'Actualizando schema...'),
        SchemaLoadStatus.ready         => (Icons.check_circle_outline, 'Listo'),
        SchemaLoadStatus.error         => (Icons.error_outline, 'Error al cargar schema'),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: _isActive ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !_isActive,
        child: _buildCard(isDark),
      ),
    );
  }

  Widget _buildCard(bool isDark) {
    final (icon, label) = _content;
    final bgColor = _isError
        ? (isDark ? const Color(0xFF5A1A1A) : const Color(0xFFB71C1C))
        : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFF0D47A1));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.25),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador animado
          _buildIndicator(icon),
          const SizedBox(width: 8),
          // Etiqueta
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(IconData icon) {
    if (_isSpinning) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    // Error o idle: ícono con pulso
    return FadeTransition(
      opacity: _pulse,
      child: Icon(icon, color: Colors.white, size: 15),
    );
  }
}
