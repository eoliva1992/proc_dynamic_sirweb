import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/snippet.dart';

class SnippetService {
  SnippetService._();

  static final instance = SnippetService._();

  static const _key = 'user_snippets';

  Future<List<Snippet>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Snippet.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(Snippet snippet) async {
    final snippets = await loadAll();
    final idx = snippets.indexWhere((s) => s.id == snippet.id);
    if (idx >= 0) {
      snippets[idx] = snippet;
    } else {
      snippets.add(snippet);
    }
    await _persist(snippets);
  }

  Future<void> delete(String id) async {
    final snippets = await loadAll();
    snippets.removeWhere((s) => s.id == id);
    await _persist(snippets);
  }

  Future<void> _persist(List<Snippet> snippets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(snippets.map((s) => s.toJson()).toList()),
    );
  }

  static String generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString();
}
