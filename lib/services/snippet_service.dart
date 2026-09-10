import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/snippet.dart';
import 'app_log.dart';

/// Result of a paginated snippets query.
typedef SnippetPage = ({
  List<Snippet> items,
  int pagina,
  int top,
  bool tieneSiguiente,
  bool tienePrevio,
});

/// Remote CRUD client for user snippets.
///
/// Endpoints:
///  - GET    /tools/snippets?ownerUser&language&isActive&query&top&pagina
///  - POST   /tools/snippets
///  - PUT    /tools/snippets/{id}
///
/// A local SharedPreferences cache keeps the last successful fetch so Monaco
/// completions keep working when the server is unreachable.
class SnippetService {
  SnippetService._();

  static final instance = SnippetService._();

  static const String baseUrl = 'http://localhost:5179/tools/snippets';
  static const _cacheKey = 'user_snippets_cache';
  static final http.Client _client = http.Client();

  /// Default owner used when creating snippets (Windows user).
  static String currentUser = (Platform.environment['USERNAME'] ?? '')
      .toUpperCase();

  // ---------------------------------------------------------------- queries

  /// Fetches snippets from the server (falls back to the local cache on error).
  Future<List<Snippet>> loadAll({
    String? ownerUser,
    String? language,
    bool? isActive = true,
    String? query,
    int top = 200,
    int pagina = 1,
  }) async {
    try {
      final page = await search(
        ownerUser: ownerUser,
        language: language,
        isActive: isActive,
        query: query,
        top: top,
        pagina: pagina,
      );
      return page.items;
    } catch (_) {
      return loadCached();
    }
  }

  /// Server-side search with pagination metadata.
  Future<SnippetPage> search({
    String? ownerUser,
    String? language,
    bool? isActive = true,
    String? query,
    int top = 50,
    int pagina = 1,
  }) async {
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        if (ownerUser != null && ownerUser.isNotEmpty) 'ownerUser': ownerUser,
        if (language != null && language.isNotEmpty && language != 'any')
          'language': language,
        if (isActive != null) 'isActive': isActive.toString(),
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        'top': '$top',
        'pagina': '$pagina',
      },
    );

    final res = await _client.get(uri, headers: const {'Accept': '*/*'});
    final body = _decode(res);
    final items = _extractItems(body);

    // Only cache full unfiltered listings.
    if ((query == null || query.trim().isEmpty) && pagina == 1) {
      await _cache(items);
    }

    return (
      items: items,
      pagina: _asInt(_pick(body, ['pagina', 'page'])) ?? pagina,
      top: _asInt(_pick(body, ['top', 'pageSize'])) ?? top,
      tieneSiguiente: _pick(body, ['tieneSiguiente']) == true,
      tienePrevio: _pick(body, ['tienePrevio']) == true,
    );
  }

  // ----------------------------------------------------------------- writes

  /// Creates (POST) or updates (PUT) a snippet and returns the persisted one.
  Future<Snippet> save(Snippet snippet) async {
    final payload = snippet.copyWith(
      ownerUser: snippet.ownerUser.isEmpty ? currentUser : snippet.ownerUser,
    );
    return payload.isPersisted ? _update(payload) : _create(payload);
  }

  Future<Snippet> _create(Snippet snippet) async {
    final res = await _client.post(
      Uri.parse(baseUrl),
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode(snippet.toCreateJson()),
    );
    return _snippetFromResponse(res, fallback: snippet);
  }

  Future<Snippet> _update(Snippet snippet) async {
    final res = await _client.put(
      Uri.parse('$baseUrl/${Uri.encodeComponent(snippet.id)}'),
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode(snippet.toUpdateJson()),
    );
    return _snippetFromResponse(
      res,
      fallback: snippet.copyWith(version: snippet.version + 1),
    );
  }

  /// Logical delete: sets `isActive = false` through the update endpoint.
  Future<void> delete(Snippet snippet) async {
    if (!snippet.isPersisted) return;
    await _update(snippet.copyWith(isActive: false));
  }

  // ------------------------------------------------------------ local cache

  Future<List<Snippet>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Snippet.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cache(List<Snippet> snippets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(snippets.map((s) => s.toJson()).toList()),
      );
    } catch (_) {
      // Cache is best-effort only.
    }
  }

  // --------------------------------------------------------------- helpers

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _errorMessage(res);
      AppLog.instance.server(
        res.request?.url.path ?? 'snippets',
        message: msg,
        statusCode: res.statusCode,
        respuesta: res.body,
        source: 'Servidor (snippets)',
      );
      throw Exception(msg);
    }
    if (res.body.trim().isEmpty) return null;
    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      AppLog.instance.server(
        res.request?.url.path ?? 'snippets',
        message: 'Respuesta inválida (no es JSON)',
        statusCode: res.statusCode,
        respuesta: res.body,
        source: 'Servidor (snippets)',
      );
      throw Exception('Respuesta inválida del servidor de snippets');
    }
    // Envelope: { success, message, data }
    if (body is Map && (body['success'] == false || body['ok'] == false)) {
      final msg =
          body['message']?.toString() ??
          body['error']?.toString() ??
          'Error en la operación de snippets';
      AppLog.instance.server(
        res.request?.url.path ?? 'snippets',
        message: msg,
        statusCode: res.statusCode,
        respuesta: res.body,
        source: 'Servidor (snippets)',
      );
      throw Exception(msg);
    }
    AppLog.instance.transaction(
      '${res.request?.method ?? 'HTTP'} ${res.request?.url.path ?? 'snippets'}',
      source: 'Snippets',
      datos: {'HTTP': res.statusCode.toString()},
    );
    return body;
  }

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map) {
        final msg = body['message'] ?? body['error'] ?? body['title'];
        if (msg != null) return '${res.statusCode}: $msg';
      }
    } catch (_) {
      // ignore
    }
    return 'HTTP ${res.statusCode} al llamar a $baseUrl';
  }

  Snippet _snippetFromResponse(http.Response res, {required Snippet fallback}) {
    final body = _decode(res);
    final map = _firstMap(body);
    if (map == null) return fallback;
    final parsed = Snippet.fromJson(map);
    return parsed.isPersisted ? parsed : fallback;
  }

  Map<String, dynamic>? _firstMap(dynamic body) {
    if (body is Map<String, dynamic>) {
      if (body['prefix'] != null || body['id'] != null) return body;
      for (final key in const ['data', 'item', 'snippet', 'result']) {
        final nested = body[key];
        if (nested is Map<String, dynamic>) return nested;
      }
    }
    if (body is List && body.isNotEmpty && body.first is Map<String, dynamic>) {
      return body.first as Map<String, dynamic>;
    }
    return null;
  }

  List<Snippet> _extractItems(dynamic body) {
    final raw = switch (body) {
      List list => list,
      Map map =>
        _firstList(map, const ['items', 'data', 'snippets', 'result']) ??
            const [],
      _ => const [],
    };
    return raw.whereType<Map<String, dynamic>>().map(Snippet.fromJson).toList();
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
