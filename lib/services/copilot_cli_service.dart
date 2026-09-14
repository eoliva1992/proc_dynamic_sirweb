import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/edit_blocks.dart';
import '../models/copilot_event.dart';

/// Estado de disponibilidad de GitHub Copilot en la máquina del usuario.
enum CopilotAuthState {
  /// Todavía no se comprobó.
  unknown,

  /// No se encontró el ejecutable `copilot` en el PATH ni en las rutas npm.
  notInstalled,

  /// La CLI existe pero no hay sesión iniciada (falta `copilot` → `/login`).
  notLoggedIn,

  /// Hay sesión pero la organización bloquea Copilot CLI o falta SSO/SAML.
  forbidden,

  /// Listo para usarse.
  ready,
}

class CopilotAuthStatus {
  final CopilotAuthState state;
  final String? executablePath;
  final String? detail;

  const CopilotAuthStatus(this.state, {this.executablePath, this.detail});

  bool get isReady => state == CopilotAuthState.ready;
}

/// Modo de trabajo del chat, equivalente al selector *Agent / Plan / Ask* de
/// Copilot Chat en VS Code.
///
/// Cada modo se traduce a un juego distinto de permisos de la CLI:
/// - [ask]: conversación pura, sin herramientas (lo más rápido).
/// - [plan]: `--plan`; la CLI redacta un plan por pasos antes de proponer nada.
/// - [agent]: deja vivos los servidores MCP configurados por el usuario (por
///   ejemplo el MCP de Sirweb) para que el agente pueda investigar. Escritura
///   de ficheros, shell y salida a internet siguen denegadas en todos los modos.
enum CopilotChatMode { agent, plan, ask }

extension CopilotChatModeX on CopilotChatMode {
  /// Identificador estable para persistir en `SharedPreferences`.
  String get id => name;

  String get label => switch (this) {
    CopilotChatMode.agent => 'Agente',
    CopilotChatMode.plan => 'Plan',
    CopilotChatMode.ask => 'Pregunta',
  };

  String get description => switch (this) {
    CopilotChatMode.agent =>
      'Usa herramientas y servidores MCP para investigar antes de responder',
    CopilotChatMode.plan =>
      'Redacta un plan por pasos antes de proponer cambios',
    CopilotChatMode.ask =>
      'Conversación directa sobre el código, sin herramientas',
  };

  static CopilotChatMode fromId(String? id) => CopilotChatMode.values
      .firstWhere((m) => m.name == id, orElse: () => CopilotChatMode.ask);
}

/// Nivel de razonamiento (`--effort`). [auto] deja decidir a la CLI.
enum CopilotEffort { auto, none, minimal, low, medium, high, xhigh, max }

extension CopilotEffortX on CopilotEffort {
  String get id => name;

  /// Valor para `--effort`; `null` cuando no hay que pasar la opción.
  String? get flagValue => this == CopilotEffort.auto ? null : name;

  String get label => switch (this) {
    CopilotEffort.auto => 'automático',
    CopilotEffort.none => 'ninguno',
    CopilotEffort.minimal => 'mínimo',
    CopilotEffort.low => 'bajo',
    CopilotEffort.medium => 'medio',
    CopilotEffort.high => 'alto',
    CopilotEffort.xhigh => 'muy alto',
    CopilotEffort.max => 'máximo',
  };

  static CopilotEffort fromId(String? id) => CopilotEffort.values.firstWhere(
    (e) => e.name == id,
    orElse: () => CopilotEffort.auto,
  );
}

/// Ventana de contexto (`--context`) para los modelos con precio por tramos.
enum CopilotContextTier { standard, long }

extension CopilotContextTierX on CopilotContextTier {
  /// Valor que entiende `--context`.
  String get flagValue =>
      this == CopilotContextTier.standard ? 'default' : 'long_context';

  String get id => name;

  String get label =>
      this == CopilotContextTier.standard ? 'estándar' : 'ampliada';

  static CopilotContextTier fromId(String? id) =>
      id == CopilotContextTier.long.name
      ? CopilotContextTier.long
      : CopilotContextTier.standard;
}

/// Pistas locales sobre la sesión, obtenidas **sin gastar una petición**.
///
/// Ninguna es una prueba definitiva (el token de la CLI vive cifrado en el
/// almacén de credenciales del sistema), pero juntas permiten mostrar al
/// usuario *por qué* la app cree que hay o no sesión.
class CopilotSessionEvidence {
  /// Cuenta de GitHub encontrada en `oauth.json` (la que usan los plugins de
  /// IDE). Es orientativa: la CLI podría estar autenticada con otra.
  final String? account;

  /// Existe el directorio de configuración de la CLI (`~/.copilot`).
  final bool hasCliConfig;

  /// Entradas relacionadas con Copilot en el almacén de credenciales.
  final int credentialEntries;

  /// Hay token en variables de entorno.
  final bool hasEnvToken;

  /// Última vez que una llamada real a la CLI funcionó.
  final DateTime? lastVerifiedOk;

  const CopilotSessionEvidence({
    this.account,
    this.hasCliConfig = false,
    this.credentialEntries = 0,
    this.hasEnvToken = false,
    this.lastVerifiedOk,
  });
}

/// Puente con **GitHub Copilot CLI**.
///
/// La app nunca gestiona credenciales de GitHub: delega en la CLI oficial, que
/// autentica por *device flow* (`copilot` → `/login`) y guarda el token en el
/// perfil del usuario. Para cuentas empresariales basta con que la
/// organización tenga habilitada la política de Copilot CLI y, si usa SAML,
/// que el token esté autorizado para la org.
///
/// Variables de entorno relevantes que se heredan/propagan al subproceso:
/// `GH_TOKEN`/`GITHUB_TOKEN` (auth no interactiva), `GH_HOST` (GHE.com con
/// residencia de datos), `HTTPS_PROXY` y `NODE_EXTRA_CA_CERTS` (proxy con
/// inspección TLS corporativa).
class CopilotCliService {
  CopilotCliService._();

  static final CopilotCliService instance = CopilotCliService._();

  static const Duration probeTimeout = Duration(seconds: 20);
  static const Duration responseTimeout = Duration(minutes: 3);

  String? _cachedExe;
  CopilotAuthStatus? _cachedStatus;
  Process? _running;

  /// El usuario pidió detener la respuesta en curso.
  ///
  /// Sin esta marca, matar el proceso produce un código de salida distinto de
  /// cero y el stream acabaría emitiendo un error falso: cancelar no es fallar.
  bool _cancelled = false;

  /// Ejecutable de Node y script de arranque de la CLI.
  ///
  /// `copilot.cmd` es solo un envoltorio que hace
  /// `node node_modules\@github\copilot\npm-loader.js %*`. Invocar Node
  /// directamente evita pasar por `cmd.exe`, cuyo límite de línea de comandos
  /// es de 8191 caracteres — insuficiente para un prompt con código. Con
  /// `CreateProcess` el tope sube a 32767.
  String? _nodeExe;
  String? _loaderJs;
  bool _launcherResolved = false;

  /// Códigos de escape ANSI que la CLI puede emitir aunque se pida `--no-color`.
  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

  /// La consola de Windows puede intercalar bytes que no son UTF-8 válido
  /// (banners, glifos de la CLI). `allowMalformed` evita que un byte suelto
  /// tire toda la respuesta con una `FormatException`.
  static const _decoder = Utf8Decoder(allowMalformed: true);

  // ── Descubrimiento del ejecutable ──────────────────────────────────────────

  /// Localiza `copilot` en el PATH y, si falla, en las rutas típicas de npm
  /// global en Windows. Devuelve `null` si no está instalado.
  Future<String?> findExecutable({bool force = false}) async {
    if (!force && _cachedExe != null) return _cachedExe;

    final locator = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(locator, ['copilot']);
      if (result.exitCode == 0) {
        final hits = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final picked = _preferLauncher(hits);
        if (picked != null) return _cachedExe = picked;
      }
    } catch (_) {
      // El localizador puede no existir — se sigue con las rutas conocidas.
    }

    for (final candidate in _fallbackPaths()) {
      if (File(candidate).existsSync()) return _cachedExe = candidate;
    }
    return null;
  }

  /// En Windows `where copilot` devuelve primero el *shim* de shell sin
  /// extensión (script bash de npm), que `Process.start` no sabe ejecutar.
  /// Hay que quedarse con el `.cmd`/`.exe`/`.bat`.
  String? _preferLauncher(List<String> hits) {
    if (hits.isEmpty) return null;
    if (!Platform.isWindows) return hits.first;
    for (final ext in const ['.cmd', '.exe', '.bat']) {
      for (final h in hits) {
        if (h.toLowerCase().endsWith(ext)) return h;
      }
    }
    return hits.first;
  }

  // ── Lanzador directo por Node (evita el límite de cmd.exe) ─────────────────

  /// Busca `node` y `npm-loader.js` junto al ejecutable detectado.
  Future<void> _resolveNodeLauncher(String exePath) async {
    if (_launcherResolved) return;
    _launcherResolved = true;
    if (!Platform.isWindows) return;

    try {
      final dir = File(exePath).parent.path;
      final loader = File(
        '$dir\\node_modules\\@github\\copilot\\npm-loader.js',
      );
      if (!loader.existsSync()) return;

      // npm instala a veces su propio node junto al shim.
      final localNode = File('$dir\\node.exe');
      if (localNode.existsSync()) {
        _nodeExe = localNode.path;
      } else {
        final r = await Process.run('where', ['node.exe']);
        if (r.exitCode == 0) {
          final first = (r.stdout as String)
              .split(RegExp(r'\r?\n'))
              .map((l) => l.trim())
              .firstWhere((l) => l.isNotEmpty, orElse: () => '');
          if (first.isNotEmpty) _nodeExe = first;
        }
      }
      if (_nodeExe != null) _loaderJs = loader.path;
    } catch (_) {
      _nodeExe = null;
      _loaderJs = null;
    }
  }

  bool get _canUseNode => _nodeExe != null && _loaderJs != null;

  /// Caracteres de prompt que caben con seguridad en la línea de comandos.
  ///
  /// Medido en Windows: por `cmd.exe` el tope real es 8191 y por
  /// `CreateProcess` 32767 (un prompt de 45 855 falla, uno de 20 355
  /// funciona). Se deja margen amplio porque el escapado de comillas que
  /// aplica Dart puede inflar la cadena.
  int get promptCharBudget => _canUseNode ? 20000 : 6000;

  List<String> _fallbackPaths() {
    final env = Platform.environment;
    final paths = <String>[];
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      final localAppData = env['LOCALAPPDATA'];
      if (appData != null) {
        paths.addAll([
          '$appData\\npm\\copilot.cmd',
          '$appData\\npm\\copilot.ps1',
        ]);
      }
      if (localAppData != null) {
        paths.add('$localAppData\\Programs\\copilot\\copilot.exe');
      }
    } else {
      final home = env['HOME'];
      paths.addAll(['/usr/local/bin/copilot', '/opt/homebrew/bin/copilot']);
      if (home != null) paths.add('$home/.local/bin/copilot');
    }
    return paths;
  }

  // ── Autenticación ──────────────────────────────────────────────────────────

  /// Rutas donde la CLI guarda su configuración y estado.
  ///
  /// Ojo: desde la versión con *credential store*, el token va al almacén de
  /// credenciales del sistema (Credential Manager en Windows) y **solo** cae a
  /// `~/.copilot/` como respaldo. Por eso esto es una pista, no una certeza.
  List<String> _credentialPaths() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'];
    final localAppData = env['LOCALAPPDATA'];
    final copilotHome = env['COPILOT_HOME'];
    final sep = Platform.isWindows ? '\\' : '/';
    final dirs = <String>[];
    if (copilotHome != null && copilotHome.isNotEmpty) dirs.add(copilotHome);
    if (home != null) dirs.add('$home$sep.copilot');
    if (localAppData != null) dirs.add('$localAppData${sep}github-copilot');
    if (home != null) dirs.add('$home$sep.config${sep}github-copilot');
    return dirs;
  }

  /// Pista de "hay sesión": existe configuración de la CLI en disco. Como el
  /// token puede vivir en el almacén de credenciales del sistema, esta
  /// heurística nunca marca *notLoggedIn* por sí sola: solo evita mostrar la
  /// app como lista cuando la CLI jamás se ha ejecutado.
  bool _hasLocalConfig() {
    for (final dir in _credentialPaths()) {
      final d = Directory(dir);
      if (d.existsSync()) return true;
    }
    return false;
  }

  /// Comprueba instalación y sesión. El resultado se cachea hasta que se
  /// llame con [force] (por ejemplo, después de que el usuario haga login).
  ///
  /// La sesión no se puede verificar de forma fiable sin gastar una petición:
  /// el token vive en el almacén de credenciales del sistema. Por eso el
  /// estado es optimista y solo pasa a [CopilotAuthState.notLoggedIn] cuando
  /// una llamada real devuelve un error de autenticación (ver
  /// [_friendlyError]).
  Future<CopilotAuthStatus> checkAuth({bool force = false}) async {
    if (!force && _cachedStatus != null) return _cachedStatus!;

    final exe = await findExecutable(force: force);
    if (exe == null) {
      return _cachedStatus = const CopilotAuthStatus(
        CopilotAuthState.notInstalled,
        detail:
            'No se encontró la CLI de Copilot. Instálala con:\n'
            'npm install -g @github/copilot',
      );
    }

    final env = Platform.environment;
    final hasToken =
        (env['COPILOT_GITHUB_TOKEN'] ??
                env['GH_TOKEN'] ??
                env['GITHUB_TOKEN'] ??
                '')
            .trim()
            .isNotEmpty;

    // Se resuelve aquí para que `promptCharBudget` sea correcto ya en la
    // primera llamada a `buildPrompt`, antes de lanzar ningún proceso.
    await _resolveNodeLauncher(exe);

    if (!hasToken && !_hasLocalConfig()) {
      return _cachedStatus = CopilotAuthStatus(
        CopilotAuthState.notLoggedIn,
        executablePath: exe,
        detail:
            'La CLI nunca se ha ejecutado en este equipo. Pulsa «Iniciar '
            'sesión» y autentícate con tu cuenta de la organización.',
      );
    }

    return _cachedStatus = CopilotAuthStatus(
      CopilotAuthState.ready,
      executablePath: exe,
    );
  }

  /// Invalida el estado cacheado (tras un login o un cambio de entorno).
  void invalidateAuthCache() {
    _cachedStatus = null;
    _cachedExe = null;
  }

  // ── Evidencia de sesión (sin gastar peticiones) ────────────────────────────

  static const _kLastVerifiedPref = 'copilot_last_verified_ok';

  /// Reúne las pistas locales de sesión para mostrarlas en la UI.
  Future<CopilotSessionEvidence> collectEvidence() async {
    final env = Platform.environment;

    final hasEnvToken =
        (env['COPILOT_GITHUB_TOKEN'] ??
                env['GH_TOKEN'] ??
                env['GITHUB_TOKEN'] ??
                '')
            .trim()
            .isNotEmpty;

    final prefs = await SharedPreferences.getInstance();
    final lastRaw = prefs.getString(_kLastVerifiedPref);

    return CopilotSessionEvidence(
      account: _readOauthAccount(),
      hasCliConfig: _hasLocalConfig(),
      credentialEntries: await _countCredentialEntries(),
      hasEnvToken: hasEnvToken,
      lastVerifiedOk: lastRaw == null ? null : DateTime.tryParse(lastRaw),
    );
  }

  /// Lee la cuenta de `oauth.json` (almacén compartido de los plugins de IDE).
  /// Nunca devuelve el token, solo la etiqueta de la cuenta.
  String? _readOauthAccount() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null) return null;
    final f = File('$localAppData\\github-copilot\\oauth.json');
    if (!f.existsSync()) return null;
    try {
      final json = jsonDecode(f.readAsStringSync());
      if (json is! Map) return null;
      for (final entries in json.values) {
        if (entries is! List) continue;
        for (final e in entries) {
          if (e is Map && e['account'] is Map) {
            final label = (e['account'] as Map)['label'];
            if (label is String && label.isNotEmpty) return label;
          }
        }
      }
    } catch (_) {
      // Formato inesperado: se ignora, es solo una pista.
    }
    return null;
  }

  /// Cuenta las entradas de Copilot en el Credential Manager de Windows.
  Future<int> _countCredentialEntries() async {
    if (!Platform.isWindows) return 0;
    try {
      final r = await Process.run('cmdkey', ['/list']);
      if (r.exitCode != 0) return 0;
      return (r.stdout as String)
          .split(RegExp(r'\r?\n'))
          .where((l) => l.toLowerCase().contains('copilot'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// **Verificación real**: lanza una consulta mínima a la CLI y observa el
  /// resultado. Es la única forma fiable de saber si la sesión sirve, porque
  /// el token está cifrado en el almacén de credenciales del sistema.
  ///
  /// Actualiza el estado cacheado y, si funciona, guarda la marca de tiempo.
  Future<CopilotAuthStatus> verifySession({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final base = await checkAuth(force: true);
    if (base.state == CopilotAuthState.notInstalled) return base;

    try {
      final buffer = StringBuffer();
      await for (final chunk in ask(
        'Responde unicamente con la palabra OK.',
        timeout: timeout,
      )) {
        buffer.write(chunk);
      }
      if (buffer.toString().trim().isEmpty) {
        return _cachedStatus = CopilotAuthStatus(
          CopilotAuthState.notLoggedIn,
          executablePath: base.executablePath,
          detail: 'La CLI no devolvió respuesta. Vuelve a iniciar sesión.',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastVerifiedPref,
        DateTime.now().toIso8601String(),
      );
      return _cachedStatus = CopilotAuthStatus(
        CopilotAuthState.ready,
        executablePath: base.executablePath,
      );
    } on CopilotCliException {
      // `ask` ya tradujo el error y dejó el estado correcto en la caché.
      return _cachedStatus ??
          CopilotAuthStatus(
            CopilotAuthState.notLoggedIn,
            executablePath: base.executablePath,
          );
    } catch (e) {
      return _cachedStatus = CopilotAuthStatus(
        CopilotAuthState.notLoggedIn,
        executablePath: base.executablePath,
        detail: 'No se pudo verificar la sesión: $e',
      );
    }
  }

  /// Abre una consola ejecutando `copilot login` para que el usuario complete
  /// el flujo OAuth con su cuenta de GitHub.
  ///
  /// Por defecto se fuerza `--web-flow`: la CLI abre el **navegador** con la
  /// pantalla de autorización de GitHub y captura el resultado en un callback
  /// loopback local. Con [deviceCode] se usa el flujo de código de dispositivo
  /// (útil si el navegador no puede abrirse o el loopback está bloqueado por
  /// políticas corporativas).
  ///
  /// Si la organización usa SAML, es en esta pantalla del navegador donde se
  /// autoriza la sesión para la org.
  Future<void> openLoginTerminal({bool deviceCode = false}) async {
    final exe = await findExecutable();
    final target = exe ?? 'copilot';
    final host =
        Platform.environment['COPILOT_GH_HOST'] ??
        Platform.environment['GH_HOST'];
    final args = <String>[
      'login',
      deviceCode ? '--device-code' : '--web-flow',
      if (host != null && host.isNotEmpty) ...[
        '--host',
        host.startsWith('http') ? host : 'https://$host',
      ],
    ];

    // El estado cacheado deja de ser válido en cuanto el usuario se
    // (re)autentica en la consola.
    invalidateAuthCache();

    if (Platform.isWindows) {
      await _startWindowsLogin(target, args);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-a', 'Terminal', '--args', target, ...args]);
    } else {
      await Process.start(target, args, runInShell: true);
    }
  }

  /// Lanza el login en una consola nueva de Windows.
  ///
  /// Se escribe un `.bat` temporal en vez de encadenar
  /// `cmd /c start "" cmd /k "<exe>" login …`: al pasar el comando completo
  /// como un único argumento, Dart escapa las comillas internas como `\"` y
  /// `cmd` responde *«"…copilot.cmd" no se reconoce como un comando…»*.
  /// El fichero por lotes evita por completo el anidamiento de comillas.
  Future<void> _startWindowsLogin(String exe, List<String> args) async {
    final bat = File('${Directory.systemTemp.path}\\sirweb_copilot_login.bat');
    await bat.writeAsString(
      '@echo off\r\n'
      'title GitHub Copilot - inicio de sesion\r\n'
      'echo Autenticando con GitHub Copilot...\r\n'
      'echo Se abrira el navegador para autorizar la sesion.\r\n'
      'echo.\r\n'
      '"$exe" ${args.join(' ')}\r\n'
      'echo.\r\n'
      'echo Listo. Vuelve a la aplicacion y pulsa "Comprobar estado".\r\n'
      'pause\r\n',
    );

    // start con título vacío ("") + ruta del .bat: cada elemento viaja como
    // argumento independiente, así que Dart los entrecomilla correctamente.
    await Process.start('cmd.exe', ['/c', 'start', '', bat.path]);
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  /// Entorno del subproceso: hereda el del usuario y añade las variables
  /// corporativas si están definidas (token, host GHE, proxy, CA interno).
  Map<String, String> _childEnvironment() {
    final env = Platform.environment;
    final extra = <String, String>{};
    for (final key in const [
      // Precedencia de token según `copilot help environment`.
      'COPILOT_GITHUB_TOKEN',
      'GH_TOKEN',
      'GITHUB_TOKEN',
      // Host: COPILOT_GH_HOST tiene prioridad sobre GH_HOST.
      'COPILOT_GH_HOST',
      'GH_HOST',
      'COPILOT_HOME',
      'COPILOT_MODEL',
      'HTTPS_PROXY',
      'HTTP_PROXY',
      'NO_PROXY',
      'NODE_EXTRA_CA_CERTS',
    ]) {
      final value = env[key];
      if (value != null && value.isNotEmpty) extra[key] = value;
    }
    // Sin color en la salida (la CLI también respeta --no-color).
    extra['NO_COLOR'] = '1';
    return extra;
  }

  /// Argumentos de la invocación no interactiva.
  ///
  /// - `-p` ejecuta el prompt y termina.
  /// - `--output-format json` emite **JSONL**: un objeto por línea, incluidos
  ///   los `assistant.message_delta` que permiten pintar la respuesta token a
  ///   token. Es incompatible en la práctica con `--silent`, que colapsa la
  ///   salida en un único bloque de texto.
  /// - `--allow-all-tools` es **obligatorio** en modo no interactivo: sin él
  ///   la CLI se queda esperando una confirmación que nadie puede dar.
  /// - Las reglas `--deny-tool` tienen precedencia sobre `--allow-all-tools`,
  ///   así que el agente queda reducido a conversar: no puede ejecutar shell,
  ///   ni escribir archivos, ni salir a la red.
  /// - `--no-remote` evita exportar la sesión a GitHub web/móvil, algo
  ///   deseable con código corporativo.
  ///
  /// Estos flags son comunes a todos los modos; lo que cambia por modo son los
  /// MCP y `--plan` (ver [_flagsForMode]).
  static const List<String> _baseFlags = [
    '--output-format',
    'json',
    '--stream',
    'on',
    '--no-color',
    '--log-level',
    'none',
    '--no-auto-update',
    '--no-ask-user',
    '--allow-all-tools',
    '--deny-tool=shell',
    '--deny-tool=write',
    '--deny-tool=url',
    '--disallow-temp-dir',
    '--no-custom-instructions',
    '--no-remote',
    '--no-remote-export',
  ];

  /// Servidores MCP que el chat admite en modo Agente.
  ///
  /// Es una **lista blanca**: cualquier otro servidor del `mcp-config.json`
  /// del usuario se apaga. Dejar vivos servidores arbitrarios daba al agente
  /// capacidades que este panel no controla, además de arrancar procesos que
  /// cuestan segundos en cada invocación.
  ///
  /// - `sqlcl`: consultar el esquema y los datos de Oracle.
  /// - `mcp-sirweb`: consultar procedimientos, eventos, tablas y autorizaciones.
  static const Set<String> allowedMcpServers = {'sqlcl', 'mcpsirweb'};

  /// Herramientas que **escriben en la base de datos**, denegadas siempre.
  ///
  /// La regla del panel es que los cambios se aplican en el editor y los
  /// guarda el usuario; el agente jamás modifica Oracle por su cuenta. Esta
  /// lista es la segunda capa de defensa: la primera es la lista blanca de
  /// servidores y la tercera, la instrucción del prompt. Se mantiene aunque
  /// dependa de que la CLI reconozca el nombre, porque el coste de un falso
  /// negativo aquí es un `UPDATE` real en producción.
  static const List<String> deniedDbWriteTools = [
    // mcp-sirweb: alta y modificación de reglas.
    'crear_procedimiento',
    'actualizar_procedimiento',
    'cambiar_estado_procedimiento',
    'compile_object_ddl',
    // mcp-sirweb: ejecución (hacen ROLLBACK, pero consumen sesión y locks).
    'ejecutar_procedimiento_dinamico',
    'ejecutar_subprograma',
    'ejecutar_llamada',
    'compilar_procedimiento_dinamico',
    // mcp-sirweb: efectos fuera de la base.
    'registrar_snippet',
    'modificar_snippet',
    'send_teams_channel_message',
    'send_teams_chat_message',
    // sqlcl: ejecución libre de SQL, que incluye DML y DDL.
    'run-sqlcl',
  ];

  static final List<String> _denyDbWriteFlags = [
    for (final t in deniedDbWriteTools) '--deny-tool=$t',
  ];

  /// Flags concretos del [mode] elegido en el panel.
  ///
  /// En *Pregunta* y *Plan* se apagan **todos** los MCP (los integrados con
  /// `--disable-builtin-mcps` y los del usuario uno a uno) porque arrancarlos
  /// cuesta segundos y no aportan nada a una respuesta conversacional. En
  /// *Agente* se dejan vivos solo los de [allowedMcpServers].
  Future<List<String>> _flagsForMode(CopilotChatMode mode) async {
    return switch (mode) {
      CopilotChatMode.ask => [
        ..._baseFlags,
        '--disable-builtin-mcps',
        ...await _disableUserMcpArgs(),
      ],
      CopilotChatMode.plan => [
        ..._baseFlags,
        '--plan',
        '--disable-builtin-mcps',
        ...await _disableUserMcpArgs(),
      ],
      CopilotChatMode.agent => [
        ..._baseFlags,
        // Los MCP integrados de la CLI tampoco pintan nada aquí.
        '--disable-builtin-mcps',
        ..._denyDbWriteFlags,
        ...await _disableUserMcpArgs(keepAllowed: true),
      ],
    };
  }

  /// Normaliza el nombre de un servidor MCP para compararlo con la lista
  /// blanca: `mcp-sirweb`, `mcp_sirweb` y `MCP Sirweb` son el mismo servidor.
  static String normalizeMcpName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// ¿Este servidor puede seguir vivo en modo Agente?
  static bool isMcpAllowed(String name) {
    final n = normalizeMcpName(name);
    return allowedMcpServers.any((a) => n == a || n.endsWith(a));
  }

  // ── Modelos disponibles ────────────────────────────────────────────────────

  /// Lista de respaldo por si la CLI no está instalada o cambia el formato de
  /// su ayuda.
  static const List<String> fallbackModels = [
    'auto',
    'claude-sonnet-5',
    'claude-opus-5',
    'gpt-5.4',
    'gpt-5.4-mini',
  ];

  List<String>? _cachedModels;

  /// Modelos que admite el `--model` de la CLI instalada.
  ///
  /// No hay ningún subcomando que los liste en JSON, pero `copilot help config`
  /// los enumera bajo la clave `model`, así que se ejecuta esa ayuda (local, no
  /// gasta peticiones) y se parsea. El resultado se cachea hasta que se llame
  /// con [force].
  Future<List<String>> listModels({bool force = false}) async {
    if (!force && _cachedModels != null) return _cachedModels!;

    final exe = await findExecutable();
    if (exe == null) return _cachedModels = fallbackModels;
    await _resolveNodeLauncher(exe);

    try {
      final result = await Process.run(
        _canUseNode ? _nodeExe! : exe,
        _canUseNode ? [_loaderJs!, 'help', 'config'] : ['help', 'config'],
        runInShell: _canUseNode ? false : Platform.isWindows,
        environment: _childEnvironment(),
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(probeTimeout);

      final models = parseModelsFromHelp('${result.stdout}\n${result.stderr}');
      if (models.isNotEmpty) return _cachedModels = ['auto', ...models];
    } catch (_) {
      // Ayuda ilegible o CLI que no responde: se usa la lista de respaldo.
    }
    return _cachedModels = fallbackModels;
  }

  /// Extrae los identificadores del bloque `model:` de `copilot help config`,
  /// donde aparecen como `- "claude-sonnet-5"`.
  @visibleForTesting
  static List<String> parseModelsFromHelp(String help) {
    final lines = help.replaceAll(_ansi, '').split(RegExp(r'\r?\n'));
    final header = RegExp(r'^\s*`?model`?\s*:');
    final entry = RegExp(r'^\s*-\s*"([^"]+)"\s*$');
    final models = <String>[];

    var inBlock = false;
    for (final line in lines) {
      if (!inBlock) {
        if (header.hasMatch(line)) inBlock = true;
        continue;
      }
      final match = entry.firstMatch(line);
      if (match != null) {
        final value = match.group(1)!.trim();
        if (value.isNotEmpty && !models.contains(value)) models.add(value);
        continue;
      }
      // Primera línea que ya no es un elemento de la lista: fin del bloque.
      // Solo cuenta si se recogió algo, para tolerar líneas en blanco entre el
      // encabezado y la enumeración.
      if (models.isNotEmpty) break;
    }
    return models;
  }

  /// Servidores MCP del usuario, leídos de `~/.copilot/mcp-config.json`.
  ///
  /// Arrancarlos cuesta varios segundos en cada invocación (medido: 14,5 s con
  /// ellos frente a 10,0 s sin ellos) y ninguno aporta nada a un chat de
  /// PL/SQL, así que se desactivan uno a uno: `--disable-builtin-mcps` solo
  /// afecta a los integrados.
  List<String>? _mcpDisableArgs;
  List<String>? _mcpAgentArgs;

  /// Argumentos para apagar los servidores MCP del usuario.
  ///
  /// Con [keepAllowed] se respetan los de [allowedMcpServers] y se apagan los
  /// demás, que es lo que necesita el modo Agente.
  Future<List<String>> _disableUserMcpArgs({bool keepAllowed = false}) async {
    final cache = keepAllowed ? _mcpAgentArgs : _mcpDisableArgs;
    if (cache != null) return cache;

    final args = <String>[];
    try {
      for (final name in await _userMcpServerNames()) {
        if (keepAllowed && isMcpAllowed(name)) continue;
        args.addAll(['--disable-mcp-server', name]);
      }
    } catch (_) {
      // Sin configuración legible no hay nada que desactivar.
    }
    return keepAllowed ? (_mcpAgentArgs = args) : (_mcpDisableArgs = args);
  }

  /// Nombres de los servidores MCP declarados por el usuario.
  Future<List<String>> _userMcpServerNames() async {
    final nombres = <String>[];
    for (final dir in _credentialPaths()) {
      final f = File('$dir${Platform.isWindows ? '\\' : '/'}mcp-config.json');
      if (!f.existsSync()) continue;
      final json = jsonDecode(await f.readAsString());
      if (json is Map && json['mcpServers'] is Map) {
        for (final name in (json['mcpServers'] as Map).keys) {
          if (name is String && name.isNotEmpty) nombres.add(name);
        }
      }
      break;
    }
    return nombres;
  }

  /// Recorta [text] a [maxChars] conservando el principio y el final, que es
  /// donde suele estar la información útil de un procedimiento (cabecera y
  /// bloque final). Marca el hueco para que el modelo sepa que falta código.
  static String trimToBudget(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars <= 200) return text.substring(0, maxChars);

    const marker = '\n\n[… fragmento omitido por tamaño …]\n\n';
    final keep = maxChars - marker.length;
    final head = (keep * 0.65).round();
    final tail = keep - head;
    return text.substring(0, head) +
        marker +
        text.substring(text.length - tail);
  }

  /// Construye el prompt: instrucciones del dominio + contexto del editor.
  ///
  /// Con sesiones reanudables ([askEvents] con `resume: true`) la CLI ya
  /// conserva el hilo, así que en los turnos siguientes se pasa
  /// [isFollowUp] en `true` y se omiten el preámbulo y el historial: solo
  /// viajan la pregunta y el contexto que haya cambiado.
  ///
  /// [maxChars] limita el tamaño total; por defecto usa [promptCharBudget],
  /// que depende de si se puede lanzar la CLI por Node o hay que pasar por
  /// `cmd.exe`.
  /// Contrato que enmarca toda respuesta: el entregable es el **editor**.
  ///
  /// Se manda en cada turno, no solo en el primero. El motivo es empírico: la
  /// sesión de la CLI conserva el hilo, pero el modelo deriva y a partir de la
  /// segunda pregunta empieza a proponer cambios contra la base de datos. La
  /// prohibición se enuncia dos veces —qué hacer y qué no— porque una lista
  /// de negativos sola tiende a ignorarse.
  static const String editorContract =
      '\nCONTEXTO DE TRABAJO: el usuario está editando una regla de negocio '
      'en el editor de procedimientos dinámicos de esta aplicación. El '
      'código que ves es el contenido de ese editor.\n'
      'TU ENTREGABLE ES SIEMPRE UNA EDICIÓN DEL DOCUMENTO, y se aplica '
      'automáticamente. Para modificar código existente usa ediciones '
      'ancladas, una por cada tramo que cambie:\n'
      '$kBuscarMarker\n'
      '(las líneas EXACTAS que hay ahora, copiadas del código de abajo)\n'
      '$kSepararMarker\n'
      '(las líneas que deben quedar)\n'
      '$kReemplazarMarker\n'
      'El tramo buscado debe aparecer UNA sola vez: incluye las líneas de '
      'alrededor que hagan falta para que sea inequívoco. No incluyas los '
      'números de línea. Usa varios bloques si hay varios cambios.\n'
      'Solo cuando reescribas el procedimiento entero, o cuando partas de '
      'cero, responde con un único bloque ```sql con el código COMPLETO y '
      'compilable. Nunca uses «-- ...» ni «/* resto igual */»: lo que '
      'omitas se perdería.\n'
      'PROHIBIDO: modificar la base de datos; proponer que se ejecute '
      'UPDATE, CREATE OR REPLACE, ALTER o DDL como acción a realizar; '
      'sugerir hacer el cambio desde SQL Developer, SQL*Plus, la consola o '
      'el propio MCP. Nada de «ejecuta esto en la base».\n'
      'Si necesitas consultar Oracle, hazlo solo para ENTENDER el contexto; '
      'el resultado de esa consulta nunca sustituye al código del editor.';

  String buildPrompt({
    required String question,
    List<ChatMessage> history = const [],
    String? code,
    String? procedimiento,
    String? ambiente,
    String? errores,
    int? maxChars,
    bool isFollowUp = false,
    CopilotChatMode mode = CopilotChatMode.ask,
  }) {
    final budget = maxChars ?? promptCharBudget;
    final b = StringBuffer();

    // Identidad y dominio: caros y estables, solo en el primer turno.
    if (!isFollowUp) {
      b.writeln(
        'Eres un asistente experto en Oracle PL/SQL y en las reglas de '
        'negocio dinámicas de Sirweb (tabla PROCEDIMIENTODINAMICO). '
        'Responde en español y de forma concisa.',
      );
    }

    // El contrato del editor viaja SIEMPRE. Enviarlo solo en el primer turno
    // hacía que el modelo perdiera el marco y, a partir de la segunda
    // pregunta, volviera a recomendar cambios contra la base de datos.
    b.writeln(editorContract);

    // El modo también se recuerda en cada turno: el usuario puede cambiarlo a
    // mitad de la conversación y la instrucción tiene que viajar con la
    // pregunta.
    switch (mode) {
      case CopilotChatMode.ask:
        break;
      case CopilotChatMode.plan:
        b.writeln(
          '\nModo Plan: antes de escribir código, expón un plan numerado con '
          'los pasos, los objetos afectados y los riesgos. Los pasos '
          'describen cómo quedará el código del editor, no tareas sobre la '
          'base de datos. No apliques cambios; espera la confirmación.',
        );
      case CopilotChatMode.agent:
        b.writeln(
          '\nModo Agente: usa sqlcl y mcp-sirweb SOLO para consultar y '
          'entender (esquema, datos, otras reglas). Nunca para crear, '
          'actualizar, compilar ni ejecutar. Consultar es un medio, no el '
          'entregable: resume en una línea qué comprobaste y termina con el '
          'PL/SQL para el editor.',
        );
    }

    if (procedimiento != null && procedimiento.isNotEmpty) {
      b.writeln('\nProcedimiento actual: $procedimiento');
    }
    if (ambiente != null && ambiente.isNotEmpty) {
      b.writeln('Ambiente: $ambiente');
    }

    // El código es lo que más ocupa. No se le puede dar el 60% a ciegas: el
    // contrato y el modo ya han consumido parte del presupuesto, así que se
    // le asigna lo que sobra tras reservar sitio para pregunta y errores.
    if (code != null && code.trim().isNotEmpty) {
      final reserva = question.length + (errores?.length ?? 0) + 200;
      final codeBudget = (budget - b.length - reserva).clamp(
        200,
        (budget * 0.6).round(),
      );
      // Numerado: ver las líneas ayuda al modelo a situarse y a copiar el
      // ancla con exactitud. Los números no forman parte del código, y el
      // contrato le dice que no los incluya al responder.
      b
        ..writeln('\nCódigo en el editor (con números de línea):')
        ..writeln('```sql')
        ..writeln(numerarLineas(trimToBudget(code.trim(), codeBudget)))
        ..writeln('```');
    }
    if (errores != null && errores.trim().isNotEmpty) {
      b
        ..writeln('\nErrores actuales:')
        ..writeln(trimToBudget(errores.trim(), (budget * 0.1).round()));
    }

    if (history.isNotEmpty) {
      // El historial se recorta desde el final: importa lo más reciente.
      final lines = <String>[];
      for (final m in history) {
        if (m.isError) continue;
        lines.add('${m.isUser ? "Usuario" : "Asistente"}: ${m.content.trim()}');
      }
      if (lines.isNotEmpty) {
        final historyBudget = (budget * 0.2).round();
        var joined = lines.join('\n');
        if (joined.length > historyBudget) {
          joined = joined.substring(joined.length - historyBudget);
        }
        b
          ..writeln('\nConversación previa:')
          ..writeln(joined);
      }
    }

    b
      ..writeln('\nPregunta:')
      ..writeln(question.trim());

    // Última red: por muy ajustadas que vayan las cuentas, el prompt
    // nunca debe superar el presupuesto recibido.
    final salida = b.toString();
    return salida.length <= budget ? salida : trimToBudget(salida, budget);
  }

  /// Envía el prompt a la CLI y emite **eventos tipados** del protocolo JSONL.
  ///
  /// Continuidad de la conversación: la primera pregunta se lanza con
  /// `--session-id <uuid>` y las siguientes con `--resume=<uuid>`. La CLI
  /// conserva el contexto en su propio almacén, de modo que **no hay que
  /// reenviar el historial** en cada turno. Eso reduce mucho el prompt y, con
  /// él, el riesgo de desbordar la línea de comandos.
  ///
  /// [model] equivale al selector de modelo de VS Code: `auto` deja que
  /// Copilot elija; cualquier otro valor se pasa con `--model`.
  ///
  /// Lanza [CopilotCliException] si la CLI no está lista o el proceso falla.
  Stream<CopilotEvent> askEvents(
    String prompt, {
    Duration? timeout,
    String? model,
    String? sessionId,
    bool resume = false,
    CopilotChatMode mode = CopilotChatMode.ask,
    CopilotEffort effort = CopilotEffort.auto,
    CopilotContextTier contextTier = CopilotContextTier.standard,
  }) async* {
    final status = await checkAuth();
    if (!status.isReady) {
      throw CopilotCliException(status.detail ?? 'Copilot no disponible');
    }

    await cancel();
    // `cancel()` deja la marca puesta; se limpia aquí, ya con el proceso
    // anterior muerto, para que la nueva petición parta de cero.
    _cancelled = false;
    await _resolveNodeLauncher(status.executablePath!);

    // Última red de seguridad: si aun así el prompt no cabe, se recorta antes
    // de llamar para no chocar con «La línea de comandos es demasiado larga».
    final safePrompt = trimToBudget(prompt, promptCharBudget);

    final useModel = (model ?? '').trim();
    final effortValue = effort.flagValue;
    final cliArgs = <String>[
      '-p',
      safePrompt,
      ...await _flagsForMode(mode),
      if (useModel.isNotEmpty && useModel != 'auto') ...['--model', useModel],
      if (effortValue != null) ...['--effort', effortValue],
      if (contextTier != CopilotContextTier.standard) ...[
        '--context',
        contextTier.flagValue,
      ],
      if (sessionId != null && sessionId.isNotEmpty)
        if (resume) '--resume=$sessionId' else ...['--session-id', sessionId],
    ];

    // Con Node se usa CreateProcess directamente (32767 caracteres); el
    // fallback por `.cmd` pasa por cmd.exe y se queda en 8191.
    final process = await Process.start(
      _canUseNode ? _nodeExe! : status.executablePath!,
      _canUseNode ? [_loaderJs!, ...cliArgs] : cliArgs,
      runInShell: _canUseNode ? false : Platform.isWindows,
      environment: _childEnvironment(),
      // La CLI carga instrucciones y busca archivos relativos al cwd: se usa
      // el temporal del sistema para no exponer el directorio de la app.
      workingDirectory: Directory.systemTemp.path,
    );
    _running = process;

    final stderrBuffer = StringBuffer();
    final stderrSub = process.stderr
        .transform(_decoder)
        .listen(stderrBuffer.write);

    final timer = Timer(timeout ?? responseTimeout, () {
      if (_running == process) {
        process.kill(ProcessSignal.sigkill);
      }
    });

    var gotContent = false;
    try {
      // JSONL: un objeto por línea. `LineSplitter` reensambla las líneas que
      // llegan partidas entre dos lecturas del pipe.
      final lines = process.stdout
          .transform(_decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        final event = CopilotEvent.tryParse(line.replaceAll(_ansi, ''));
        if (event == null || event.kind == CopilotEventKind.unknown) continue;
        if (event.kind == CopilotEventKind.delta ||
            event.kind == CopilotEventKind.message) {
          gotContent = true;
        }
        yield event;
      }

      final exitCode = await process.exitCode;
      // Al cancelar, el proceso muere con código distinto de cero: eso no es
      // un fallo que haya que enseñar al usuario, es lo que pidió.
      if (exitCode != 0 && !gotContent && !_cancelled) {
        throw CopilotCliException(
          _friendlyError(stderrBuffer.toString(), exitCode),
        );
      }
    } finally {
      timer.cancel();
      await stderrSub.cancel();
      if (_running == process) _running = null;
    }
  }

  /// Envoltorio de texto plano sobre [askEvents], para usos sencillos como la
  /// verificación de sesión.
  Stream<String> ask(String prompt, {Duration? timeout, String? model}) {
    return askEvents(
      prompt,
      timeout: timeout,
      model: model,
    ).where((e) => e.kind == CopilotEventKind.delta).map((e) => e.text ?? '');
  }

  /// Traduce los fallos más comunes de entorno corporativo a algo accionable.
  String _friendlyError(String stderr, int exitCode) {
    final text = stderr.replaceAll(_ansi, '').trim();
    final lower = text.toLowerCase();

    if (lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('not logged in') ||
        lower.contains('not authenticated') ||
        lower.contains('authentication')) {
      // El token no vive en disco, así que la única señal fiable de "sin
      // sesión" es este error: se fija el estado para que el panel muestre
      // el banner de login.
      _cachedStatus = CopilotAuthStatus(
        CopilotAuthState.notLoggedIn,
        executablePath: _cachedExe,
        detail:
            'Sesión de GitHub no válida o caducada. Pulsa «Iniciar sesión» '
            '(ejecuta «copilot login»). Si tu organización usa SAML, '
            'autoriza el token para la org.',
      );
      return _cachedStatus!.detail!;
    }
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('policy') ||
        lower.contains('no copilot') ||
        lower.contains('not enabled') ||
        lower.contains('no subscription') ||
        lower.contains('quota')) {
      _cachedStatus = CopilotAuthStatus(
        CopilotAuthState.forbidden,
        executablePath: _cachedExe,
        detail:
            'Tu organización no permite Copilot CLI con esta cuenta, o no '
            'quedan créditos. Pide al administrador que habilite la política '
            'de Copilot CLI para tu equipo.',
      );
      return _cachedStatus!.detail!;
    }
    if (lower.contains('content exclusion') || lower.contains('excluded')) {
      return 'El contenido está excluido por la política de la organización.';
    }
    if (lower.contains('demasiado larga') ||
        lower.contains('command line is too long') ||
        lower.contains('línea de comandos') ||
        lower.contains('linea de comandos')) {
      return 'El contexto es demasiado grande para enviarlo. Selecciona en el '
          'editor solo el fragmento relevante: cuando hay selección se envía '
          'únicamente esa parte en vez del procedimiento completo.';
    }
    if (lower.contains('certificate') || lower.contains('self-signed')) {
      return 'Error de certificado TLS. Define NODE_EXTRA_CA_CERTS con el CA '
          'corporativo antes de abrir la aplicación.';
    }
    if (lower.contains('proxy') || lower.contains('enotfound')) {
      return 'No hay conexión con GitHub. Revisa HTTPS_PROXY / firewall.';
    }
    if (text.isEmpty) {
      return 'La CLI de Copilot terminó con código $exitCode sin respuesta.';
    }
    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  }

  /// Mata el proceso en curso, si lo hay.
  ///
  /// En Windows no basta con `kill`: se lanza **node**, y la CLI de Copilot
  /// crea procesos hijos que sobreviven a la muerte del padre y siguen
  /// consumiendo la petición. `taskkill /T` acaba con el árbol entero.
  Future<void> cancel() async {
    final process = _running;
    if (process == null) return;
    _running = null;
    // Marca la cancelación *antes* de matar: así el `askEvents` en vuelo sabe
    // que el código de salida distinto de cero es esperado y no lo convierte
    // en un mensaje de error.
    _cancelled = true;
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', [
          '/F',
          '/T',
          '/PID',
          '${process.pid}',
        ]).timeout(const Duration(seconds: 3), onTimeout: () => _dummyResult);
      }
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (e) {
      debugPrint('Copilot cancel: $e');
    }
  }

  static final _dummyResult = ProcessResult(0, -1, '', '');

  bool get isBusy => _running != null;
}

class CopilotCliException implements Exception {
  final String message;
  CopilotCliException(this.message);
  @override
  String toString() => message;
}
