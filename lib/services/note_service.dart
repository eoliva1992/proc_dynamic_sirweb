import 'dart:convert';
import 'dart:io';
import 'dart:ui' show VoidCallback;

import 'package:http/http.dart' as http;

import '../models/note.dart';
import 'app_log.dart';
import 'server_config_service.dart';

/// Result of a paginated notes query.
typedef NotePage = ({
  List<NoteListItem> items,
  int pagina,
  int top,
  bool tieneSiguiente,
  bool tienePrevio,
});

/// Remote CRUD + sharing client for user notes.
///
/// Endpoints:
///  - GET    /tools/notas?requestingUser&tag&query&isActive&top&pagina
///  - GET    /tools/notas/{id}?requestingUser
///  - POST   /tools/notas
///  - PUT    /tools/notas/{id}
///  - DELETE /tools/notas/{id}?requestingUser
///  - POST   /tools/notas/{id}/compartir
///  - DELETE /tools/notas/{id}/compartir?ownerUser&targetUser
///  - GET    /tools/notas/{id}/comparticiones?ownerUser
class NoteService {
  NoteService._();

  static final instance = NoteService._();

  static final http.Client _client = http.Client();

  /// Default owner/requesting user (Windows user).
  static String currentUser = (Platform.environment['USERNAME'] ?? '')
      .toUpperCase();

  /// Callbacks to close all active note floating windows and modals when
  /// resetting the module (e.g., when the active user changes).
  static final Set<VoidCallback> _activeClosers = <VoidCallback>{};

  /// Registers a closer callback for an open note window or browser dialog.
  static void registerCloser(VoidCallback closer) {
    _activeClosers.add(closer);
  }

  /// Unregisters a previously registered closer callback.
  static void unregisterCloser(VoidCallback closer) {
    _activeClosers.remove(closer);
  }

  /// Closes all active note windows/dialogs and updates the current active user.
  static void resetForUser(String newUser) {
    currentUser = newUser.trim().toUpperCase();
    final closers = List<VoidCallback>.from(_activeClosers);
    for (final close in closers) {
      try {
        close();
      } catch (e) {
        AppLog.instance.error(
          'Error cerrando ventana de nota durante reset: $e',
        );
      }
    }
    _activeClosers.clear();
  }

  static Future<String> getBaseUrl() async {
    final baseUrl = await ServerConfigService().getBaseUrl();
    return '$baseUrl/tools/notas';
  }

  // ---------------------------------------------------------------- queries

  Future<NotePage> search({
    String? requestingUser,
    String? tag,
    String? query,
    bool? isActive = true,
    int top = 50,
    int pagina = 1,
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        if (requestingUser != null && requestingUser.isNotEmpty)
          'requestingUser': requestingUser,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if (isActive != null) 'isActive': isActive.toString(),
        'top': '$top',
        'pagina': '$pagina',
      },
    );

    final res = await _client.get(uri, headers: const {'Accept': '*/*'});
    final body = _decode(res);
    final items = _extractItems(body);

    return (
      items: items,
      pagina: _asInt(_pick(body, ['pagina', 'page'])) ?? pagina,
      top: _asInt(_pick(body, ['top', 'pageSize'])) ?? top,
      tieneSiguiente: _pick(body, ['tieneSiguiente']) == true,
      tienePrevio: _pick(body, ['tienePrevio']) == true,
    );
  }

  Future<NoteListItem> getById(
    String id, {
    required String requestingUser,
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse(
      '$baseUrl/${Uri.encodeComponent(id)}',
    ).replace(queryParameters: {'requestingUser': requestingUser});
    final res = await _client.get(uri, headers: const {'Accept': '*/*'});
    final body = _decode(res);
    final map = _firstMap(body);
    if (map == null) {
      throw Exception('Respuesta inválida al obtener la nota');
    }
    return NoteListItem.fromJson(map);
  }

  // ----------------------------------------------------------------- writes

  Future<Note> create(Note note) async {
    final payload = note.copyWith(
      ownerUser: note.ownerUser.isEmpty ? currentUser : note.ownerUser,
    );
    final baseUrl = await getBaseUrl();
    final res = await _client.post(
      Uri.parse(baseUrl),
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode(payload.toCreateJson()),
    );
    return _noteFromResponse(res, fallback: payload);
  }

  Future<Note> update(Note note, {required String requestingUser}) async {
    final baseUrl = await getBaseUrl();
    final res = await _client.put(
      Uri.parse('$baseUrl/${Uri.encodeComponent(note.id)}'),
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode(note.toUpdateJson(requestingUser: requestingUser)),
    );
    return _noteFromResponse(
      res,
      fallback: note.copyWith(version: note.version + 1),
    );
  }

  /// Saves (create or update) depending on [note.isPersisted].
  Future<Note> save(Note note, {required String requestingUser}) {
    return note.isPersisted
        ? update(note, requestingUser: requestingUser)
        : create(note);
  }

  Future<void> delete(String id, {required String requestingUser}) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse(
      '$baseUrl/${Uri.encodeComponent(id)}',
    ).replace(queryParameters: {'requestingUser': requestingUser});
    final res = await _client.delete(uri, headers: const {'Accept': '*/*'});
    _decode(res);
  }

  // ---------------------------------------------------------------- sharing

  /// Builds the compact `asignaciones` string (e.g. `ana:ReadOnly,juan:Edit`)
  /// and shares the note with all the given users in a single call.
  Future<NoteShareResult> share(
    String id, {
    required String ownerUser,
    required Map<String, NotePermission> grants,
  }) async {
    final asignaciones = grants.entries
        .map((e) => '${e.key}:${e.value.asignacionLabel}')
        .join(',');
    final baseUrl = await getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl/${Uri.encodeComponent(id)}/compartir'),
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode({'ownerUser': ownerUser, 'asignaciones': asignaciones}),
    );
    final body = _decode(res);
    final map = _firstMap(body);
    if (map == null) {
      throw Exception('Respuesta inválida al compartir la nota');
    }
    return NoteShareResult.fromJson(map);
  }

  Future<void> revokeShare(
    String id, {
    required String ownerUser,
    required String targetUser,
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/${Uri.encodeComponent(id)}/compartir')
        .replace(
          queryParameters: {
            'ownerUser': ownerUser,
            'targetUsers': targetUser,
            'targetUser': targetUser,
          },
        );
    final res = await _client.delete(uri, headers: const {'Accept': '*/*'});
    _decode(res);
  }

  Future<List<NoteShare>> listShares(
    String id, {
    required String ownerUser,
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse(
      '$baseUrl/${Uri.encodeComponent(id)}/comparticiones',
    ).replace(queryParameters: {'ownerUser': ownerUser});
    final res = await _client.get(uri, headers: const {'Accept': '*/*'});
    final body = _decode(res);
    final raw = switch (body) {
      List list => list,
      Map map => _firstList(map, const ['items', 'data', 'result']) ?? const [],
      _ => const [],
    };
    return raw
        .whereType<Map<String, dynamic>>()
        .map(NoteShare.fromJson)
        .toList();
  }

  // --------------------------------------------------------------- helpers

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _errorMessage(res);
      AppLog.instance.server(
        res.request?.url.path ?? 'notas',
        message: msg,
        statusCode: res.statusCode,
        respuesta: res.body,
        source: 'Servidor (notas)',
      );
      throw Exception(msg);
    }
    if (res.body.trim().isEmpty) return null;
    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      AppLog.instance.server(
        res.request?.url.path ?? 'notas',
        message: 'Respuesta inválida (no es JSON)',
        statusCode: res.statusCode,
        respuesta: res.body,
        source: 'Servidor (notas)',
      );
      throw Exception('Respuesta inválida del servidor de notas');
    }
    // Envelope: { success, message, error, data }
    if (body is Map && (body['success'] == false || body['ok'] == false)) {
      final msg =
          body['message']?.toString() ??
          body['error']?.toString() ??
          'Error en la operación de notas';
      AppLog.instance.server(
        res.request?.url.path ?? 'notas',
        message: msg,
        statusCode: res.statusCode,
        respuesta: res.body,
        source: 'Servidor (notas)',
      );
      throw Exception(msg);
    }
    AppLog.instance.transaction(
      '${res.request?.method ?? 'HTTP'} ${res.request?.url.path ?? 'notas'}',
      source: 'Notas',
      datos: {'HTTP': res.statusCode.toString()},
    );
    return body;
  }

  String _errorMessage(http.Response res) {
    try {
      final raw = utf8.decode(res.bodyBytes).trim();
      if (raw.isEmpty) return 'HTTP ${res.statusCode} al llamar a notas';
      final dynamic body = jsonDecode(raw);
      if (body is Map) {
        final msg =
            body['message'] ?? body['error'] ?? body['title'] ?? body['detail'];
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return '${res.statusCode}: $msg';
        }
        if (body['errors'] is Map) {
          final errMap = body['errors'] as Map;
          final details = errMap.entries
              .map(
                (e) =>
                    '${e.key}: ${e.value is List ? (e.value as List).join(", ") : e.value}',
              )
              .join('; ');
          if (details.isNotEmpty) return '${res.statusCode}: $details';
        }
      } else if (body is String && body.trim().isNotEmpty) {
        return '${res.statusCode}: $body';
      }
    } catch (_) {
      final text = String.fromCharCodes(res.bodyBytes).trim();
      if (text.isNotEmpty && text.length < 200) {
        return '${res.statusCode}: $text';
      }
    }
    return 'HTTP ${res.statusCode} al llamar a notas';
  }

  Note _noteFromResponse(http.Response res, {required Note fallback}) {
    final body = _decode(res);
    final map = _firstMap(body);
    if (map == null) return fallback;
    final parsed = Note.fromJson(map);
    return parsed.isPersisted ? parsed : fallback;
  }

  Map<String, dynamic>? _firstMap(dynamic body) {
    if (body is Map<String, dynamic>) {
      if (body['note'] != null || body['title'] != null || body['id'] != null) {
        return body;
      }
      for (final key in const ['data', 'item', 'note', 'result']) {
        final nested = body[key];
        if (nested is Map<String, dynamic>) return nested;
      }
    }
    if (body is List && body.isNotEmpty && body.first is Map<String, dynamic>) {
      return body.first as Map<String, dynamic>;
    }
    return null;
  }

  List<NoteListItem> _extractItems(dynamic body) {
    final raw = switch (body) {
      List list => list,
      Map map =>
        _firstList(map, const ['items', 'data', 'notas', 'result']) ?? const [],
      _ => const [],
    };
    return raw
        .whereType<Map<String, dynamic>>()
        .map(NoteListItem.fromJson)
        .toList();
  }

  List<dynamic>? _firstList(Map map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is List) return v;
      if (v is Map) {
        final nested = _firstList(v, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  dynamic _pick(dynamic body, List<String> keys) {
    if (body is Map) {
      for (final k in keys) {
        if (body[k] != null) return body[k];
      }
      for (final k in const ['data', 'result']) {
        final nested = body[k];
        if (nested is Map) return _pick(nested, keys);
      }
    }
    return null;
  }

  int? _asInt(dynamic v) => switch (v) {
    num n => n.toInt(),
    String s => int.tryParse(s),
    _ => null,
  };
}
