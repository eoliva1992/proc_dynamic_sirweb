import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Lee una respuesta MCP y devuelve el JSON del **primer evento `data:`**.
///
/// El servidor MCP responde con `Content-Type: text/event-stream` y mantiene el
/// stream abierto después de enviar el resultado. Por eso no se puede usar
/// `client.post()` (que espera el EOF del cuerpo): el `Future` quedaría colgado
/// aunque los datos ya hubieran llegado, dejando la UI con el spinner activo.
///
/// Esta función corta en cuanto llega el primer evento `data:` y cancela la
/// suscripción para liberar la conexión persistente. Si la respuesta es JSON
/// plano (sin SSE), devuelve el cuerpo completo al cerrarse el stream.
Future<String> readFirstSseData(
  http.StreamedResponse response, {
  required String toolName,
  required Duration timeout,
}) {
  final completer = Completer<String>();
  final buffer = StringBuffer();
  late final StreamSubscription<String> sub;
  Timer? timer;

  void finish(void Function() action) {
    timer?.cancel();
    // Cancelar libera la conexión aunque el SSE siga abierto del lado servidor.
    sub.cancel().catchError((_) {});
    action();
  }

  sub = response.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          if (completer.isCompleted) return;
          if (line.startsWith('data: ')) {
            finish(() => completer.complete(line.substring(6)));
          } else {
            buffer.writeln(line);
          }
        },
        onError: (Object e, StackTrace st) {
          if (completer.isCompleted) return;
          finish(() => completer.completeError(e, st));
        },
        onDone: () {
          if (completer.isCompleted) return;
          timer?.cancel();
          final raw = buffer.toString().trim();
          if (raw.isEmpty) {
            completer.completeError(
              Exception('MCP $toolName: respuesta vacía'),
            );
          } else {
            completer.complete(raw);
          }
        },
        cancelOnError: true,
      );

  timer = Timer(timeout, () {
    if (completer.isCompleted) return;
    finish(
      () => completer.completeError(
        TimeoutException('MCP $toolName: sin respuesta', timeout),
      ),
    );
  });

  return completer.future;
}
