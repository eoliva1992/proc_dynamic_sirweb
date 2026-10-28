import 'package:shared_preferences/shared_preferences.dart';

/// Tipo de autenticación para operaciones de Git remoto.
enum GitAuthType {
  token,
  ssh;

  static GitAuthType fromString(String? val) {
    if (val?.toLowerCase() == 'ssh') return GitAuthType.ssh;
    return GitAuthType.token;
  }
}

/// Modelo con la configuración del repositorio Git remoto, local y credenciales.
class GitRepositoryConfig {
  /// Enlace remoto al servidor del repositorio (Azure DevOps, GitLab, GitHub, etc.)
  /// Representa `rutaRepositorio` en el ticket.
  final String rutaRepositorio;

  /// Ruta local en disco donde se encuentra clonado el proyecto y donde se guardan los scripts.
  /// Representa `rutaDirectorioLocal` en el ticket.
  final String rutaDirectorioLocal;

  /// Tipo de autenticación: `GitAuthType.token` (HTTPS con Personal Access Token) o `GitAuthType.ssh`.
  final GitAuthType authType;

  /// Token de acceso personal (PAT) almacenado en la app para autorización HTTPS.
  final String personalAccessToken;

  const GitRepositoryConfig({
    this.rutaRepositorio = '',
    this.rutaDirectorioLocal = '',
    this.authType = GitAuthType.token,
    this.personalAccessToken = '',
  });

  /// Indica si la configuración base (rutas) está completa para crear o enlazar ramas.
  bool get isConfigured =>
      rutaRepositorio.trim().isNotEmpty &&
      rutaDirectorioLocal.trim().isNotEmpty;

  /// Indica si está listo para realizar `git push` con autorización.
  bool get isPushReady {
    if (!isConfigured) return false;
    if (authType == GitAuthType.token) {
      return personalAccessToken.trim().isNotEmpty;
    }
    // Con SSH asume que la clave local o agente SSH está configurado
    return true;
  }

  GitRepositoryConfig copyWith({
    String? rutaRepositorio,
    String? rutaDirectorioLocal,
    GitAuthType? authType,
    String? personalAccessToken,
  }) {
    return GitRepositoryConfig(
      rutaRepositorio: rutaRepositorio ?? this.rutaRepositorio,
      rutaDirectorioLocal: rutaDirectorioLocal ?? this.rutaDirectorioLocal,
      authType: authType ?? this.authType,
      personalAccessToken: personalAccessToken ?? this.personalAccessToken,
    );
  }
}

/// Servicio que gestiona la persistencia de la configuración del repositorio Git en disco.
class GitRepositoryConfigService {
  static final GitRepositoryConfigService _instance =
      GitRepositoryConfigService._();
  factory GitRepositoryConfigService() => _instance;
  GitRepositoryConfigService._();

  static const String _prefKeyRepoPath = 'git_repo_ruta_repositorio';
  static const String _prefKeyLocalPath = 'git_repo_ruta_directorio_local';
  static const String _prefKeyAuthType = 'git_repo_auth_type';
  static const String _prefKeyToken = 'git_repo_personal_access_token';

  GitRepositoryConfig? _cachedConfig;

  /// Obtiene la configuración guardada (o desde SharedPreferences)
  Future<GitRepositoryConfig> getConfig() async {
    if (_cachedConfig != null) {
      return _cachedConfig!;
    }

    final prefs = await SharedPreferences.getInstance();
    final repo = prefs.getString(_prefKeyRepoPath) ?? '';
    final local = prefs.getString(_prefKeyLocalPath) ?? '';
    final authStr = prefs.getString(_prefKeyAuthType) ?? 'token';
    final token = prefs.getString(_prefKeyToken) ?? '';

    _cachedConfig = GitRepositoryConfig(
      rutaRepositorio: repo,
      rutaDirectorioLocal: local,
      authType: GitAuthType.fromString(authStr),
      personalAccessToken: token,
    );
    return _cachedConfig!;
  }

  /// Retorna la configuración cacheada en memoria si existe
  GitRepositoryConfig getConfigSync() {
    return _cachedConfig ?? const GitRepositoryConfig();
  }

  /// Guarda una nueva configuración de repositorio
  Future<void> saveConfig({
    required String rutaRepositorio,
    required String rutaDirectorioLocal,
    GitAuthType authType = GitAuthType.token,
    String personalAccessToken = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyRepoPath, rutaRepositorio.trim());
    await prefs.setString(_prefKeyLocalPath, rutaDirectorioLocal.trim());
    await prefs.setString(_prefKeyAuthType, authType.name);
    await prefs.setString(_prefKeyToken, personalAccessToken.trim());

    _cachedConfig = GitRepositoryConfig(
      rutaRepositorio: rutaRepositorio.trim(),
      rutaDirectorioLocal: rutaDirectorioLocal.trim(),
      authType: authType,
      personalAccessToken: personalAccessToken.trim(),
    );
  }

  /// Limpia la configuración
  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyRepoPath);
    await prefs.remove(_prefKeyLocalPath);
    await prefs.remove(_prefKeyAuthType);
    await prefs.remove(_prefKeyToken);
    _cachedConfig = const GitRepositoryConfig();
  }
}
