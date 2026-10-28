import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
import 'git_repository_config_service.dart';

/// Resultado de la ejecución de un comando Git
class GitCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final String command;

  const GitCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.command,
  });

  bool get isSuccess => exitCode == 0;

  String get output => stdout.isNotEmpty ? stdout : stderr;

  @override
  String toString() =>
      'GitCommandResult(cmd: $command, exitCode: $exitCode, out: $stdout, err: $stderr)';
}

/// Servicio que encapsula operaciones Git mediante CLI local (`Process.run`).
///
/// Todas las operaciones se ejecutan dentro del directorio raíz local del repositorio
/// (`workingDirectory: rutaDirectorioLocal`).
class GitService {
  final String workingDirectory;

  const GitService({required this.workingDirectory});

  /// Ejecuta un comando git con los argumentos especificados
  Future<GitCommandResult> runGit(
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final cmdStr = 'git ${args.join(' ')}';
    try {
      final env = <String, String>{'GIT_TERMINAL_PROMPT': '0', ...?environment};

      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
        environment: env,
      );

      final cmdResult = GitCommandResult(
        exitCode: result.exitCode,
        stdout: (result.stdout ?? '').toString().trim(),
        stderr: (result.stderr ?? '').toString().trim(),
        command: cmdStr,
      );

      if (!cmdResult.isSuccess) {
        AppLog.instance.warning(
          'Git fallo ($cmdStr): ${cmdResult.stderr}',
          source: 'GitService',
        );
      } else {
        AppLog.instance.info(
          'Git ok ($cmdStr): ${cmdResult.stdout}',
          source: 'GitService',
        );
      }
      return cmdResult;
    } catch (e) {
      AppLog.instance.error(
        'Excepción al ejecutar $cmdStr: $e',
        source: 'GitService',
      );
      return GitCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
        command: cmdStr,
      );
    }
  }

  /// Verifica si la CLI de Git está disponible en el PATH del sistema
  static Future<bool> isGitInstalled() async {
    try {
      final res = await Process.run('git', ['--version'], runInShell: true);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Valida si el directorio configurado es un repositorio Git válido
  Future<bool> isGitRepository() async {
    if (workingDirectory.trim().isEmpty) return false;
    final dir = Directory(workingDirectory);
    if (!dir.existsSync()) return false;

    final res = await runGit(['rev-parse', '--is-inside-work-tree']);
    return res.isSuccess && res.stdout.toLowerCase().contains('true');
  }

  /// Obtiene la rama actual activa
  Future<String?> getCurrentBranch() async {
    final res = await runGit(['rev-parse', '--abbrev-ref', 'HEAD']);
    if (res.isSuccess && res.stdout.isNotEmpty) {
      return res.stdout.trim();
    }
    return null;
  }

  /// Verifica si una rama ya existe localmente
  Future<bool> branchExists(String branchName) async {
    final res = await runGit(['branch', '--list', branchName]);
    return res.isSuccess && res.stdout.trim().isNotEmpty;
  }

  /// Determina si la rama base principal local es `master` o `main`
  Future<String> resolveDefaultBaseBranch() async {
    if (await branchExists('master')) return 'master';
    if (await branchExists('main')) return 'main';
    // Si ninguna existe con list, probar rev-parse
    final resMaster = await runGit(['rev-parse', '--verify', 'master']);
    if (resMaster.isSuccess) return 'master';
    final resMain = await runGit(['rev-parse', '--verify', 'main']);
    if (resMain.isSuccess) return 'main';
    return 'master';
  }

  /// Cambia a una rama existente
  Future<GitCommandResult> checkout(String branchName) async {
    return runGit(['checkout', branchName]);
  }

  /// Crea una nueva rama y se posiciona en ella (`git checkout -b <branchName>`)
  ///
  /// Opcionalmente permite especificar [startPoint] (por ejemplo 'master' o 'main').
  Future<GitCommandResult> createAndCheckoutBranch(
    String branchName, {
    String? startPoint,
  }) async {
    final args = ['checkout', '-b', branchName];
    if (startPoint != null && startPoint.trim().isNotEmpty) {
      args.add(startPoint.trim());
    }
    return runGit(args);
  }

  /// Agrega archivos al staging (`git add <path>`)
  Future<GitCommandResult> add(String path) async {
    return runGit(['add', path]);
  }

  /// Agrega una lista de archivos individuales al staging
  Future<GitCommandResult> addFiles(List<String> relativePaths) async {
    return runGit(['add', '--', ...relativePaths]);
  }

  /// Realiza un commit con el mensaje indicado
  Future<GitCommandResult> commit(String message) async {
    return runGit(['commit', '-m', message]);
  }

  /// Configura o actualiza la URL del remoto `origin` si se proporciona `remoteUrl`
  Future<GitCommandResult> syncRemoteOrigin(String remoteUrl) async {
    final cleanUrl = remoteUrl.trim();
    if (cleanUrl.isEmpty) {
      return GitCommandResult(
        exitCode: 0,
        stdout: 'No remoteUrl specified',
        stderr: '',
        command: 'syncRemoteOrigin',
      );
    }

    final remotes = await runGit(['remote']);
    final hasOrigin = remotes.stdout.split(RegExp(r'\r?\n')).contains('origin');

    if (hasOrigin) {
      return runGit(['remote', 'set-url', 'origin', cleanUrl]);
    } else {
      return runGit(['remote', 'add', 'origin', cleanUrl]);
    }
  }

  /// Ejecuta un pull desde el remoto (`git pull <remote> <branch>`) con soporte
  /// para autenticación segura (PAT / SSH).
  Future<GitCommandResult> pull({
    String remote = 'origin',
    String? branch,
    String? remoteUrl,
    GitAuthType authType = GitAuthType.token,
    String? token,
  }) async {
    if (remoteUrl != null && remoteUrl.trim().isNotEmpty) {
      await syncRemoteOrigin(remoteUrl.trim());
    }

    final args = <String>[];
    final env = <String, String>{'GIT_TERMINAL_PROMPT': '0'};

    if (authType == GitAuthType.token &&
        token != null &&
        token.trim().isNotEmpty) {
      final pat = token.trim();
      final basicAuth = base64Encode(utf8.encode('pat:$pat'));
      args.addAll(['-c', 'http.extraHeader=Authorization: Basic $basicAuth']);
    } else if (authType == GitAuthType.ssh) {
      env['GIT_SSH_COMMAND'] = 'ssh -o BatchMode=yes';
    }

    args.addAll(['pull', remote]);
    if (branch != null && branch.trim().isNotEmpty) {
      args.add(branch.trim());
    }

    return runGit(args, environment: env);
  }

  /// Hace push de la rama actual o especificada al remoto (`git push -u origin <branchName>`)
  ///
  /// Soporta autorización mediante:
  /// - `GitAuthType.token` (Personal Access Token): inyecta un encabezado HTTP efímero
  ///   `Authorization: Basic <base64>` sin exponer el token de forma permanente en .git/config.
  /// - `GitAuthType.ssh`: ejecuta con `GIT_SSH_COMMAND: 'ssh -o BatchMode=yes'` para evitar prompts.
  Future<GitCommandResult> push({
    required String branchName,
    String remote = 'origin',
    String? remoteUrl,
    GitAuthType authType = GitAuthType.token,
    String? token,
  }) async {
    // Si se especificó una URL remota, sincronizarla previamente con el remoto
    if (remoteUrl != null && remoteUrl.trim().isNotEmpty) {
      await syncRemoteOrigin(remoteUrl.trim());
    }

    final args = <String>[];
    final env = <String, String>{'GIT_TERMINAL_PROMPT': '0'};

    if (authType == GitAuthType.token &&
        token != null &&
        token.trim().isNotEmpty) {
      final pat = token.trim();
      // Codificar en Basic Auth: "pat:<token>"
      final basicAuth = base64Encode(utf8.encode('pat:$pat'));
      args.addAll(['-c', 'http.extraHeader=Authorization: Basic $basicAuth']);
    } else if (authType == GitAuthType.ssh) {
      env['GIT_SSH_COMMAND'] = 'ssh -o BatchMode=yes';
    }

    args.addAll(['push', '-u', remote, branchName]);
    return runGit(args, environment: env);
  }

  /// Obtiene el estado resumido del repositorio (`git status --short`)
  Future<GitCommandResult> status() async {
    return runGit(['status', '--short']);
  }

  /// Sanitiza el número de solicitud y genera el nombre oficial sugerido:
  /// `hf_{numeroSolicitud_sanitizado}_{yymmdd}`
  static String formatHotfixBranchName({
    required String numeroSolicitud,
    DateTime? date,
  }) {
    final sanitizedSol = numeroSolicitud
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .trim();
    final d = date ?? DateTime.now();
    final yy = (d.year % 100).toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final dateStr = '$yy$mm$dd';

    final base = sanitizedSol.isNotEmpty ? sanitizedSol : 'ticket';
    return 'hf_${base}_$dateStr';
  }

  /// Limpia y traduce un mensaje de error devuelto por `git ls-remote`
  static String cleanRemoteErrorMessage(String stderr) {
    final lower = stderr.toLowerCase();
    if (lower.contains('repository not found') || lower.contains('not found')) {
      return 'El repositorio no existe o no se tiene acceso a la URL proporcionada.';
    }
    if (lower.contains('authentication failed') ||
        lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('could not read username')) {
      return 'Error de autenticación. El token (PAT) o credencial es inválido o no tiene permisos.';
    }
    if (lower.contains('permission denied')) {
      return 'Permiso denegado por el servidor remoto.';
    }
    if (lower.contains('could not resolve host') ||
        lower.contains('name or service not known')) {
      return 'No se pudo resolver el host del servidor. Comprueba la conexión o la URL.';
    }
    if (lower.contains('connection timed out') || lower.contains('timed out')) {
      return 'Tiempo de espera agotado al conectar con el servidor remoto.';
    }
    if (lower.contains('connection refused')) {
      return 'Conexión rechazada por el servidor remoto.';
    }
    if (lower.contains('unable to access')) {
      // Extraer fragmento útil si existe
      final match = RegExp(
        r"unable to access '.*?': (.*)",
        caseSensitive: false,
      ).firstMatch(stderr);
      if (match != null && match.groupCount >= 1) {
        return 'No se pudo acceder al remoto: ${match.group(1)?.trim()}';
      }
      return 'No se pudo acceder a la URL del repositorio.';
    }

    // Si tiene líneas fatal: extraer la línea
    final fatalLine = stderr
        .split(RegExp(r'\r?\n'))
        .firstWhere(
          (l) => l.trim().toLowerCase().startsWith('fatal:'),
          orElse: () => '',
        );
    if (fatalLine.isNotEmpty) {
      return fatalLine
          .replaceFirst(RegExp(r'fatal:\s*', caseSensitive: false), '')
          .trim();
    }

    final trimmed = stderr.trim();
    return trimmed.isNotEmpty
        ? trimmed
        : 'Error desconocido al validar acceso al repositorio.';
  }

  /// Valida la validez de un Personal Access Token (PAT) o credenciales contra un repositorio remoto
  /// ejecutando `git ls-remote --heads <url>` sin necesidad de que el repositorio esté clonado previamente.
  static Future<GitRemoteValidationResult> validateRemoteAccessToken({
    required String remoteUrl,
    required String personalAccessToken,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final trimmedUrl = remoteUrl.trim();
    final trimmedPat = personalAccessToken.trim();

    if (trimmedUrl.isEmpty) {
      return const GitRemoteValidationResult(
        isValid: false,
        message: 'La URL del repositorio remoto no puede estar vacía.',
      );
    }

    if (trimmedPat.isEmpty) {
      return const GitRemoteValidationResult(
        isValid: false,
        message: 'El Personal Access Token (PAT) no puede estar vacío.',
      );
    }

    final basicAuth = base64Encode(utf8.encode('pat:$trimmedPat'));
    final args = <String>[
      '-c',
      'http.extraHeader=Authorization: Basic $basicAuth',
      'ls-remote',
      '--heads',
      trimmedUrl,
    ];

    try {
      final processResult = await Process.run(
        'git',
        args,
        environment: {'GIT_TERMINAL_PROMPT': '0'},
      ).timeout(timeout);

      final isSuccess = processResult.exitCode == 0;
      final stdout = (processResult.stdout as String?) ?? '';
      final stderr = (processResult.stderr as String?) ?? '';

      if (isSuccess) {
        final branches = stdout
            .split(RegExp(r'\r?\n'))
            .where((l) => l.contains('refs/heads/'))
            .map((l) => l.split('refs/heads/').last.trim())
            .where((b) => b.isNotEmpty)
            .toList();

        final branchSummary = branches.isNotEmpty
            ? 'Conexión verificada (${branches.length} rama${branches.length == 1 ? '' : 's'} disponible${branches.length == 1 ? '' : 's'})'
            : 'Conexión verificada con éxito.';

        return GitRemoteValidationResult(
          isValid: true,
          message: branchSummary,
          detectedBranches: branches,
        );
      } else {
        final cleanedError = cleanRemoteErrorMessage(stderr);
        return GitRemoteValidationResult(
          isValid: false,
          message: cleanedError,
          rawError: stderr,
        );
      }
    } on TimeoutException {
      return const GitRemoteValidationResult(
        isValid: false,
        message:
            'Tiempo de espera agotado al intentar conectar con el servidor remoto.',
      );
    } catch (e) {
      return GitRemoteValidationResult(
        isValid: false,
        message: 'Error al ejecutar git ls-remote: $e',
      );
    }
  }
}

/// Resultado de la validación remota de credenciales y URL Git
class GitRemoteValidationResult {
  final bool isValid;
  final String message;
  final String? rawError;
  final List<String> detectedBranches;

  const GitRemoteValidationResult({
    required this.isValid,
    required this.message,
    this.rawError,
    this.detectedBranches = const [],
  });
}
