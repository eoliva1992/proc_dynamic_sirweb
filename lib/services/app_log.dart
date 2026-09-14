import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Severidad de una entrada del log.
enum LogLevel { debug, info, success, warning, error }

extension LogLevelLabel on LogLevel {
  String get label => switch (this) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.success => 'OK',
    LogLevel.warning => 'WARN',
    LogLevel.error => 'ERROR',
  };
}

/// Una línea del log de la aplicación.
@immutable
class LogEntry {
  final DateTime time;
  final LogLevel level;

  /// Origen: `Compilación`, `Transferencia`, `Oracle`, `App`, …
  final String source;
  final String message;

  /// Texto largo asociado (errores `ORA-`, DDL ejecutado, stack, …).
  final String? detail;

  const LogEntry({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    this.detail,
  });

  String get hhmmss {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(time.hour)}:${p(time.minute)}:${p(time.second)}';
  }

  /// Representación en texto plano (para copiar / exportar).
  String get asText {
    final head = '[$hhmmss] ${level.label.padRight(5)} $source — $message';
    if (detail == null || detail!.trim().isEmpty) return head;
    final body = detail!
        .trimRight()
        .split('\n')
        .map((l) => '    $l')
        .join('\n');
    return '$head\n$body';
  }
}

/// Log central de la aplicación: alimenta la consola integrada.
///
/// Es un [ChangeNotifier] singleton; cualquier widget puede escucharlo con
/// `ListenableBuilder(listenable: AppLog.instance, …)`.
///
/// Todo lo que se informa por toast se registra también acá, además de los
/// errores de compilación (con línea/columna) y las transferencias entre
/// ambientes, que quedan con su detalle completo aunque el toast desaparezca.
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// Máximo de entradas retenidas (se descartan las más viejas).
  static const int maxEntries = 1000;

  final List<LogEntry> _entries = [];

  /// Entradas de la más nueva a la más vieja.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  /// Errores registrados desde la última vez que se abrió/limpió la consola.
  int _unseenErrors = 0;
  int get unseenErrors => _unseenErrors;

  /// Marca los errores como vistos (se llama al abrir la consola).
  void markSeen() {
    if (_unseenErrors == 0) return;
    _unseenErrors = 0;
    _notify();
  }

  /// Notifica a los oyentes sin romper la fase de build.
  ///
  /// El log se alimenta desde cualquier punto de la app (incluidos el `build`
  /// o el `didUpdateWidget` de un widget). Notificar en ese momento marca como
  /// sucios a los `ListenableBuilder` que escuchan el log y Flutter lanza
  /// *"setState() or markNeedsBuild() called during build"*. Si estamos
  /// construyendo, la notificación se difiere al final del frame.
  void _notify() {
    SchedulerBinding? binding;
    try {
      binding = SchedulerBinding.instance;
    } catch (_) {
      // Sin binding (tests de Dart puro): se notifica directamente.
      binding = null;
    }
    if (binding != null &&
        binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => notifyListeners());
      return;
    }
    notifyListeners();
  }

  void add(
    LogLevel level,
    String message, {
    String source = 'App',
    String? detail,
  }) {
    if (message.trim().isEmpty) return;
    _entries.insert(
      0,
      LogEntry(
        time: DateTime.now(),
        level: level,
        source: source,
        message: message.trim(),
        detail: detail,
      ),
    );
    if (_entries.length > maxEntries)
      _entries.removeRange(maxEntries, _entries.length);
    if (level == LogLevel.error) _unseenErrors++;
    _notify();
  }

  void debug(String m, {String source = 'App', String? detail}) =>
      add(LogLevel.debug, m, source: source, detail: detail);
  void info(String m, {String source = 'App', String? detail}) =>
      add(LogLevel.info, m, source: source, detail: detail);
  void success(String m, {String source = 'App', String? detail}) =>
      add(LogLevel.success, m, source: source, detail: detail);
  void warning(String m, {String source = 'App', String? detail}) =>
      add(LogLevel.warning, m, source: source, detail: detail);
  void error(String m, {String source = 'App', String? detail}) =>
      add(LogLevel.error, m, source: source, detail: detail);

  /// Cantidad de entradas por nivel (para los filtros de la consola).
  int countOf(LogLevel level) => _entries.where((e) => e.level == level).length;

  /// Registra una transacción completada: qué se hizo, con qué datos y cuánto
  /// tardó. Es el registro "normal" de la actividad de la app (nivel info).
  ///
  /// ```
  /// AppLog.instance.transaction('Guardar procedimiento', source: 'Procedimientos',
  ///   datos: {'Código': 'DR_X', 'Ambiente': 'Desa'}, duracion: elapsed);
  /// ```
  void transaction(
    String accion, {
    String source = 'App',
    Map<String, String?> datos = const {},
    Duration? duracion,
    LogLevel level = LogLevel.info,
    String? detalle,
  }) {
    final buffer = StringBuffer();
    for (final e in datos.entries) {
      final v = e.value;
      if (v == null || v.trim().isEmpty) continue;
      buffer.writeln('${e.key.padRight(10)}: ${v.trim()}');
    }
    if (detalle != null && detalle.trim().isNotEmpty) {
      buffer.writeln(_clip(detalle.trim(), 1200));
    }
    add(
      level,
      duracion == null ? accion : '$accion · ${_ms(duracion)}',
      source: source,
      detail: buffer.isEmpty ? null : buffer.toString(),
    );
  }

  static String _ms(Duration d) => d.inMilliseconds >= 1000
      ? '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s'
      : '${d.inMilliseconds} ms';

  /// Registra el resultado de compilar un objeto en Oracle.
  ///
  /// Con [errors] vacío queda una línea de éxito; si hay errores el encabezado
  /// describe el **primer** problema (`PLS-00103: …`) y el detalle lista todos
  /// con su línea y columna, de modo que el diagnóstico completo sobreviva al
  /// cierre del panel de errores.
  void compilation({
    required String objectName,
    required String objectType,
    required String ambiente,
    required List<({int line, int position, String text, String attribute})>
    errors,
    String source = 'Compilación',
    String? part,
  }) {
    final label = part != null
        ? '$objectName ($objectType $part) en $ambiente'
        : '$objectName ($objectType) en $ambiente';
    if (errors.isEmpty) {
      success('Compilado OK — $label', source: source);
      return;
    }
    final soloErrores = errors.where((e) => e.attribute == 'ERROR').length;
    final primero = errors.first;
    final resto = errors.length > 1 ? ' (+${errors.length - 1} más)' : '';
    final detail = errors
        .map(
          (e) =>
              '${e.attribute} línea ${e.line}, col ${e.position}: '
              '${e.text.trim()}',
        )
        .join('\n');
    add(
      soloErrores > 0 ? LogLevel.error : LogLevel.warning,
      '$label — línea ${primero.line}: ${_oneLine(primero.text)}$resto',
      source: source,
      detail: detail,
    );
  }

  /// Registra una sentencia DDL ejecutada contra un ambiente (GRANT, SYNONYM…).
  void ddl(
    String ddl, {
    required String ambiente,
    String? errorMessage,
    String source = 'DDL',
  }) {
    if (errorMessage == null) {
      success('$ambiente · ${_oneLine(ddl)}', source: source);
    } else {
      error(
        '$ambiente · falló ${_oneLine(ddl)}',
        source: source,
        detail: errorMessage,
      );
    }
  }

  static String _oneLine(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 160 ? t : '${t.substring(0, 157)}…';
  }

  /// Registra una excepción describiendo qué pasó, dónde y con qué datos.
  ///
  /// [contexto] indica la operación en curso ("Compilar OBJ_RECIBOS en QA");
  /// [error] se descompone en su descripción y su tipo, y se agregan los
  /// [datos] extra (DDL enviado, ambiente, objeto…) y el stack si lo hay.
  void exception(
    String contexto,
    Object error, {
    StackTrace? stack,
    String source = 'App',
    Map<String, String?> datos = const {},
  }) {
    final desc = describe(error);
    final buffer = StringBuffer()
      ..writeln('Tipo      : ${error.runtimeType}')
      ..writeln('Mensaje   : $desc');
    for (final e in datos.entries) {
      final v = e.value;
      if (v == null || v.trim().isEmpty) continue;
      buffer.writeln('${e.key.padRight(10)}: ${v.trim()}');
    }
    final ora = oracleCodes(desc);
    if (ora.isNotEmpty) buffer.writeln('Códigos   : ${ora.join(', ')}');
    if (stack != null) {
      final lineas = stack.toString().split('\n').take(8).join('\n');
      buffer
        ..writeln('Stack     :')
        ..writeln(lineas);
    }
    add(
      LogLevel.error,
      '$contexto — ${_oneLine(desc)}',
      source: source,
      detail: buffer.toString(),
    );
  }

  /// Mensaje legible de una excepción (sin el prefijo `Exception:`).
  static String describe(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(Exception|Error): '), '').trim();

  /// Códigos Oracle (`ORA-…`, `PLS-…`) presentes en [texto], sin repetir.
  static List<String> oracleCodes(String texto) => RegExp(
    r'\b(?:ORA|PLS|PLW|SP2)-\d{3,5}\b',
  ).allMatches(texto).map((m) => m.group(0)!).toSet().toList();

  /// Registra una respuesta de error del backend (MCP o REST).
  ///
  /// Queda asentado exactamente **qué devolvió el servidor**: el endpoint o la
  /// herramienta invocada, el código HTTP si lo hay, el mensaje/`error` del
  /// envelope, los argumentos enviados y la respuesta cruda recortada.
  void server(
    String endpoint, {
    required String message,
    Map<String, dynamic>? argumentos,
    int? statusCode,
    String? respuesta,
    LogLevel level = LogLevel.error,
    String source = 'Servidor',
  }) {
    final buffer = StringBuffer()..writeln('Endpoint  : $endpoint');
    if (statusCode != null) buffer.writeln('HTTP      : $statusCode');
    buffer.writeln('Mensaje   : ${message.trim()}');
    final ora = oracleCodes(message);
    if (ora.isNotEmpty) buffer.writeln('Códigos   : ${ora.join(', ')}');
    if (argumentos != null && argumentos.isNotEmpty) {
      buffer
        ..writeln('Argumentos:')
        ..writeln(_prettyArgs(argumentos));
    }
    if (respuesta != null && respuesta.trim().isNotEmpty) {
      buffer
        ..writeln('Respuesta :')
        ..writeln(_clip(respuesta.trim(), 1500));
    }
    add(
      level,
      '$endpoint — ${_oneLine(message)}',
      source: source,
      detail: buffer.toString(),
    );
  }

  /// Argumentos en JSON legible, recortando los valores largos (p. ej. un DDL).
  static String _prettyArgs(Map<String, dynamic> args) {
    final recortado = <String, dynamic>{
      for (final e in args.entries)
        e.key: e.value is String ? _clip(e.value as String, 600) : e.value,
    };
    try {
      return const JsonEncoder.withIndent('  ').convert(recortado);
    } catch (_) {
      return recortado.toString();
    }
  }

  static String _clip(String s, int max) => s.length <= max
      ? s
      : '${s.substring(0, max)}… (+${s.length - max} chars)';

  void clear() {
    _entries.clear();
    _unseenErrors = 0;
    _notify();
  }

  /// Todo el log en texto plano, de la entrada más vieja a la más nueva.
  String asText() => _entries.reversed.map((e) => e.asText).join('\n');
}
