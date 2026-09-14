import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de configuración del servidor base.
/// Permite cambiar dinámicamente la dirección del servidor sin recompilar.
class ServerConfigService {
  static final ServerConfigService _instance = ServerConfigService._();
  factory ServerConfigService() => _instance;
  ServerConfigService._();

  static const String _prefKeyBaseUrl = 'server_base_url';
  static const String _defaultBaseUrl = 'http://localhost:5179';

  /// Caché en memoria de la URL base actual
  String? _cachedBaseUrl;

  /// Obtiene la URL base del servidor (del caché o de SharedPreferences)
  Future<String> getBaseUrl() async {
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }

    final prefs = await SharedPreferences.getInstance();
    _cachedBaseUrl = prefs.getString(_prefKeyBaseUrl) ?? _defaultBaseUrl;
    return _cachedBaseUrl!;
  }

  /// Obtiene la URL base sin esperar (caché en memoria)
  /// Retorna el valor cacheado o el default si aún no se ha cargado
  String getBaseUrlSync() {
    return _cachedBaseUrl ?? _defaultBaseUrl;
  }

  /// Establece una nueva URL base del servidor
  Future<void> setBaseUrl(String newUrl) async {
    // Validar que sea una URL válida
    if (newUrl.isEmpty) {
      throw ArgumentError('La URL del servidor no puede estar vacía');
    }

    try {
      Uri.parse(newUrl);
    } catch (_) {
      throw ArgumentError('URL inválida: $newUrl');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyBaseUrl, newUrl);
    _cachedBaseUrl = newUrl;
  }

  /// Reinicia a la URL por defecto
  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyBaseUrl);
    _cachedBaseUrl = _defaultBaseUrl;
  }

  /// Obtiene el valor por defecto
  static String getDefault() => _defaultBaseUrl;
}

