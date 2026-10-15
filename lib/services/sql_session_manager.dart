import 'package:flutter/foundation.dart';

/// Centraliza y gestiona las sesiones Oracle activas (`sessionId`) por ambiente.
///
/// Permite que múltiples pestañas del Ejecutor SQL conectadas al mismo
/// ambiente (ej. 'Desa', 'QA', 'Prod') compartan la misma transacción abierta
/// sin hacer commit prematuro. Al ejecutar un INSERT en una pestaña y un SELECT
/// en otra, ambas verán la misma transacción y datos no confirmados.
class SqlSessionManager extends ChangeNotifier {
  static final SqlSessionManager _instance = SqlSessionManager._();
  factory SqlSessionManager() => _instance;
  static SqlSessionManager get instance => _instance;

  SqlSessionManager._();

  final Map<String, String> _sessionsByAmbiente = {};

  /// Devuelve el `sessionId` activo para el [ambiente] dado, o `null` si no hay
  /// transacción abierta en curso.
  String? getSessionId(String ambiente) => _sessionsByAmbiente[ambiente];

  /// Indica si el [ambiente] tiene una transacción activa con cambios pendientes.
  bool hasPendingChanges(String ambiente) =>
      _sessionsByAmbiente.containsKey(ambiente);

  /// Registra o actualiza el [sessionId] de una transacción para el [ambiente].
  void setSessionId(String ambiente, String? sessionId) {
    if (sessionId == null || sessionId.trim().isEmpty) {
      clearSession(ambiente);
      return;
    }
    if (_sessionsByAmbiente[ambiente] == sessionId) return;
    _sessionsByAmbiente[ambiente] = sessionId;
    notifyListeners();
  }

  /// Limpia la sesión del [ambiente] (p. ej. tras commit, rollback o desconexión).
  void clearSession(String ambiente) {
    if (_sessionsByAmbiente.remove(ambiente) != null) {
      notifyListeners();
    }
  }

  /// Limpia todas las sesiones activas en todos los ambientes (útil para tests o reset).
  @visibleForTesting
  void reset() {
    if (_sessionsByAmbiente.isNotEmpty) {
      _sessionsByAmbiente.clear();
      notifyListeners();
    }
  }
}
