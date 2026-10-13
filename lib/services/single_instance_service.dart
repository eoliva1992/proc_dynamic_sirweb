import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Garantiza una única instancia de la ventana principal: si la app ya está
/// corriendo, el nuevo proceso (lanzado p. ej. vía "Abrir con" de Windows)
/// reenvía su argumento (ruta de archivo) a la instancia activa y termina,
/// en vez de abrir una segunda ventana.
abstract final class SingleInstanceService {
  // Puerto fijo en loopback usado como lock + canal IPC entre instancias.
  static const int _port = 48562;

  static ServerSocket? _server;

  /// Emite la ruta de archivo recibida de una instancia secundaria para que
  /// la ventana principal la abra como pestaña nueva.
  static final filePathRequests = StreamController<String>.broadcast();

  /// Notifica que una segunda instancia intentó abrirse (sin archivo), para
  /// traer la ventana principal al frente.
  static final focusRequests = StreamController<void>.broadcast();

  /// Intenta convertirse en la instancia principal. Devuelve `true` si lo
  /// logró (el caller debe continuar con `runApp`). Devuelve `false` si ya
  /// había una instancia corriendo: en ese caso el argumento ya fue
  /// reenviado y el proceso actual debe terminar sin crear ventana.
  static Future<bool> acquireOrForward(String? filePath) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
    } on SocketException {
      await _forwardToRunningInstance(filePath);
      return false;
    }
    _server!.listen(_handleClient, onError: (_) {});
    return true;
  }

  static void _handleClient(Socket client) {
    client.cast<List<int>>().transform(utf8.decoder).listen((data) {
      final path = data.trim();
      if (path.isNotEmpty) {
        filePathRequests.add(path);
      } else {
        focusRequests.add(null);
      }
    }, onError: (_) {});
    unawaited(client.close());
  }

  static Future<void> _forwardToRunningInstance(String? filePath) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 2),
      );
      socket.write(filePath ?? '');
      await socket.flush();
      await socket.close();
    } catch (e) {
      debugPrint(
        '[SingleInstanceService] No se pudo reenviar al proceso principal: $e',
      );
    }
  }
}
