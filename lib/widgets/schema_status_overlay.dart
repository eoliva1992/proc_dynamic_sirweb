import 'dart:async';
import 'package:flutter/material.dart';
import '../services/schema_service.dart';
import 'status_card.dart';

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
    SchemaLoadStatus.idle => (Icons.dns_outlined, 'Schema no cargado'),
    SchemaLoadStatus.loadingLocal => (Icons.storage, 'Leyendo schema local...'),
    SchemaLoadStatus.loadingServer => (
      Icons.cloud_download_outlined,
      'Descargando schema del servidor...',
    ),
    SchemaLoadStatus.refreshing => (Icons.sync, 'Actualizando schema...'),
    SchemaLoadStatus.ready => (Icons.check_circle_outline, 'Listo'),
    SchemaLoadStatus.error => (Icons.error_outline, 'Error al cargar schema'),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: _isActive ? 1.0 : 0.0,
      child: IgnorePointer(ignoring: !_isActive, child: _buildCard(isDark)),
    );
  }

  Widget _buildCard(bool isDark) {
    final (icon, label) = _content;
    return StatusCard(
      message: label,
      isSpinning: _isSpinning,
      isError: _isError,
      icon: icon,
    );
  }
}
