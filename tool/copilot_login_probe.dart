// Diagnóstico del chat de Copilot — ver docs/copilot-chat.md.
//
// Comprueba, sin gastar peticiones ni créditos, todo lo que la app necesita
// para hablar con la CLI: ejecutable, lanzador por Node, presupuesto de prompt
// y pistas de sesión. Útil al preparar un equipo nuevo o cuando el panel falla.
//
// Uso: dart run tool/copilot_login_probe.dart
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final env = Platform.environment;
  stdout.writeln('== Diagnóstico de GitHub Copilot ==\n');

  // 1. Ejecutable de la CLI. Se prefiere .cmd/.exe: `where copilot` devuelve
  //    primero el shim de shell sin extensión, que CreateProcess no ejecuta.
  final exe = await _findCli();
  stdout.writeln('CLI:                ${exe ?? "NO ENCONTRADA"}');

  // 2. Lanzador por Node: `copilot.cmd` solo ejecuta
  //    `node node_modules\@github\copilot\npm-loader.js`. Invocar Node
  //    directamente evita el límite de 8191 caracteres de cmd.exe.
  var canUseNode = false;
  if (exe != null && Platform.isWindows) {
    final dir = File(exe).parent.path;
    final loader = File('$dir\\node_modules\\@github\\copilot\\npm-loader.js');
    final node = await _findNode(dir);
    canUseNode = loader.existsSync() && node != null;
    stdout.writeln('Node:               ${node ?? "no encontrado"}');
    stdout.writeln(
      'npm-loader.js:      ${loader.existsSync() ? loader.path : "no encontrado"}',
    );
  }
  stdout.writeln(
    'Vía de lanzamiento: ${canUseNode ? "Node (directo)" : "copilot.cmd (shell)"}',
  );
  stdout.writeln(
    'Presupuesto prompt: ${canUseNode ? 20000 : 6000} caracteres\n',
  );

  // 3. Pistas de sesión. El token real está cifrado en el almacén de
  //    credenciales del sistema, así que solo se puede inferir.
  final home = env['USERPROFILE'] ?? env['HOME'];
  final cfg = home == null
      ? false
      : Directory('$home${Platform.pathSeparator}.copilot').existsSync();
  stdout.writeln('Config de la CLI:   ${cfg ? "presente" : "ausente"}');

  if (Platform.isWindows) {
    try {
      final r = await Process.run('cmdkey', ['/list']);
      final n = (r.stdout as String)
          .split(RegExp(r'\r?\n'))
          .where((l) => l.toLowerCase().contains('copilot'))
          .length;
      stdout.writeln('Credenciales:       $n entradas de Copilot');
    } catch (_) {
      stdout.writeln('Credenciales:       no se pudo consultar');
    }
  }

  final cuenta = _readOauthAccount(env['LOCALAPPDATA']);
  stdout.writeln('Cuenta detectada:   ${cuenta ?? "ninguna"}');

  final token =
      env['COPILOT_GITHUB_TOKEN'] ?? env['GH_TOKEN'] ?? env['GITHUB_TOKEN'];
  stdout.writeln(
    'Token de entorno:   ${(token ?? '').isNotEmpty ? "definido" : "no definido"}',
  );

  for (final k in const [
    'GH_HOST',
    'COPILOT_GH_HOST',
    'HTTPS_PROXY',
    'NODE_EXTRA_CA_CERTS',
  ]) {
    final v = env[k];
    if (v != null && v.isNotEmpty) stdout.writeln('$k: $v');
  }

  stdout.writeln(
    '\nSi la CLI no aparece:  npm install -g @github/copilot'
    '\nSi falta la sesión:    copilot login',
  );
}

Future<String?> _findCli() async {
  final locator = Platform.isWindows ? 'where' : 'which';
  try {
    final r = await Process.run(locator, ['copilot']);
    if (r.exitCode != 0) return null;
    final hits = (r.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (hits.isEmpty) return null;
    if (!Platform.isWindows) return hits.first;
    for (final ext in const ['.cmd', '.exe', '.bat']) {
      for (final h in hits) {
        if (h.toLowerCase().endsWith(ext)) return h;
      }
    }
    return hits.first;
  } catch (_) {
    return null;
  }
}

Future<String?> _findNode(String cliDir) async {
  if (File('$cliDir\\node.exe').existsSync()) return '$cliDir\\node.exe';
  try {
    final r = await Process.run('where', ['node.exe']);
    if (r.exitCode != 0) return null;
    final first = (r.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return first.isEmpty ? null : first;
  } catch (_) {
    return null;
  }
}

/// Lee solo la etiqueta de la cuenta de `oauth.json`; nunca el token.
String? _readOauthAccount(String? localAppData) {
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
  } catch (_) {}
  return null;
}

