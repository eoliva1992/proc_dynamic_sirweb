import 'dart:async';
import 'package:flutter/foundation.dart';
import '../providers/procedimientos_provider.dart';

/// Representa el estado de una sesión de conexión Oracle para un par (ambiente, owner).
class _SqlSessionEntry {
  final String sessionId;
  bool hasPendingChanges;
  DateTime lastActivity;
  Timer? idleTimer;

  _SqlSessionEntry({
    required this.sessionId,
    this.hasPendingChanges = false,
    DateTime? lastActivity,
  }) : lastActivity = lastActivity ?? DateTime.now();
}

/// Centraliza y gestiona las sesiones Oracle activas (`sessionId`) por
/// par compuesto (ambiente, owner).
///
/// Permite que múltiples pestañas del Ejecutor SQL conectadas al mismo
/// ambiente (ej. 'Desa', 'QA', 'Prod') y bajo el mismo dueño (ej. 'TESTUSER')
/// compartan la misma sesión y transacción abierta sin agotar el pool de
/// conexiones del backend de Oracle.
///
/// La sesión NO se destruye al hacer commit o rollback; únicamente se actualiza
/// el estado de `hasPendingChanges`. La sesión solo se descarta por tiempo de
/// inactividad (por defecto 30 minutos sin ejecutar sentencias), o cuando se
/// invoca explícitamente `clearSession`.
class SqlSessionManager extends ChangeNotifier {
  static final SqlSessionManager _instance = SqlSessionManager._();
  factory SqlSessionManager() => _instance;
  static SqlSessionManager get instance => _instance;

  SqlSessionManager._();

  /// Tiempo de inactividad antes de descartar automáticamente la sesión en el cliente.
  Duration idleTimeout = const Duration(minutes: 30);

  final Map<String, _SqlSessionEntry> _sessions = {};

  String _normalizeKey(String ambiente, String? owner) {
    final effectiveOwner = (owner != null && owner.trim().isNotEmpty)
        ? owner.trim()
        : procedimientosProvider.cdUsuario.trim();
    return '${ambiente.trim().toUpperCase()}|${effectiveOwner.toUpperCase()}';
  }

  /// Devuelve el `sessionId` activo para el [ambiente] y [owner] dados, o `null`
  /// si no hay sesión registrada.
  String? getSessionId(String ambiente, {String? owner}) {
    final key = _normalizeKey(ambiente, owner);
    return _sessions[key]?.sessionId;
  }

  /// Indica si el [ambiente] y [owner] tienen una transacción activa con cambios pendientes.
  bool hasPendingChanges(String ambiente, {String? owner}) {
    final key = _normalizeKey(ambiente, owner);
    return _sessions[key]?.hasPendingChanges ?? false;
  }

  /// Registra o actualiza el [sessionId] para el par ([ambiente], [owner]).
  /// Si [hasPendingChanges] no se especifica, conserva el valor previo (o false por defecto).
  void setSessionId(
    String ambiente,
    String? sessionId, {
    String? owner,
    bool? hasPendingChanges,
  }) {
    final key = _normalizeKey(ambiente, owner);
    if (sessionId == null || sessionId.trim().isEmpty) {
      clearSession(ambiente, owner: owner);
      return;
    }

    final trimmedId = sessionId.trim();
    final existing = _sessions[key];
    final pending = hasPendingChanges ?? (existing?.hasPendingChanges ?? false);

    if (existing != null &&
        existing.sessionId == trimmedId &&
        existing.hasPendingChanges == pending) {
      _touchEntry(key, existing);
      return;
    }

    existing?.idleTimer?.cancel();
    final entry = _SqlSessionEntry(
      sessionId: trimmedId,
      hasPendingChanges: pending,
      lastActivity: DateTime.now(),
    );
    _scheduleIdleTimer(key, entry);
    _sessions[key] = entry;
    notifyListeners();
  }

  /// Actualiza únicamente el estado de cambios pendientes para el par ([ambiente], [owner]),
  /// preservando el [sessionId] intacto (usado tras COMMIT o ROLLBACK).
  void markPendingChanges(
    String ambiente,
    bool pending, {
    String? owner,
  }) {
    final key = _normalizeKey(ambiente, owner);
    final entry = _sessions[key];
    if (entry == null) return;

    _touchEntry(key, entry);
    if (entry.hasPendingChanges != pending) {
      entry.hasPendingChanges = pending;
      notifyListeners();
    }
  }

  /// Refresca la marca temporal de última actividad y renueva el temporizador de inactividad.
  void touch(String ambiente, {String? owner}) {
    final key = _normalizeKey(ambiente, owner);
    final entry = _sessions[key];
    if (entry != null) {
      _touchEntry(key, entry);
    }
  }

  void _touchEntry(String key, _SqlSessionEntry entry) {
    entry.lastActivity = DateTime.now();
    entry.idleTimer?.cancel();
    _scheduleIdleTimer(key, entry);
  }

  void _scheduleIdleTimer(String key, _SqlSessionEntry entry) {
    if (idleTimeout <= Duration.zero) return;
    entry.idleTimer = Timer(idleTimeout, () {
      final current = _sessions[key];
      if (identical(current, entry)) {
        _sessions.remove(key);
        notifyListeners();
      }
    });
  }

  /// Notifica a los oyentes de cambios externos (por ejemplo, cambio de usuario actual).
  void notifyExternalChange() {
    notifyListeners();
  }

  /// Limpia la sesión del par ([ambiente], [owner]) (p. ej. tras timeout, error de conexión
  /// o cierre explícito).
  void clearSession(String ambiente, {String? owner}) {
    final key = _normalizeKey(ambiente, owner);
    final removed = _sessions.remove(key);
    if (removed != null) {
      removed.idleTimer?.cancel();
      notifyListeners();
    }
  }

  /// Limpia todas las sesiones activas en todos los ambientes (útil para tests o reset).
  @visibleForTesting
  void reset() {
    if (_sessions.isNotEmpty) {
      for (final entry in _sessions.values) {
        entry.idleTimer?.cancel();
      }
      _sessions.clear();
      notifyListeners();
    }
  }
}
