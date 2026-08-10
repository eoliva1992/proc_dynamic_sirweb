import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SchemaObjectRef {
  final String name;
  final String type;
  final String owner;
  final String ambiente;

  const SchemaObjectRef({
    required this.name,
    required this.type,
    required this.ambiente,
    this.owner = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'owner': owner,
    'ambiente': ambiente,
  };

  factory SchemaObjectRef.fromJson(Map<String, dynamic> json) =>
      SchemaObjectRef(
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        owner: json['owner'] as String? ?? '',
        ambiente: json['ambiente'] as String? ?? 'Desa',
      );
}

/// Persiste objetos recientemente visitados y favoritos en SharedPreferences.
class SchemaRecentsService {
  SchemaRecentsService._();
  static final SchemaRecentsService instance = SchemaRecentsService._();

  static const _kRecents = 'schema_recents_v2';
  static const _kFavorites = 'schema_favorites_v2';
  static const _maxRecents = 20;

  Future<void> addRecent(SchemaObjectRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _load(prefs, _kRecents);
    list.removeWhere((r) => r.name == ref.name && r.ambiente == ref.ambiente);
    list.insert(0, ref);
    while (list.length > _maxRecents) {
      list.removeLast();
    }
    await _save(prefs, _kRecents, list);
  }

  Future<List<SchemaObjectRef>> getRecents({String? ambiente}) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _load(prefs, _kRecents);
    if (ambiente == null) return all;
    return all.where((r) => r.ambiente == ambiente).toList();
  }

  Future<void> addFavorite(SchemaObjectRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _load(prefs, _kFavorites);
    if (!list.any((r) => r.name == ref.name && r.ambiente == ref.ambiente)) {
      list.add(ref);
      await _save(prefs, _kFavorites, list);
    }
  }

  Future<void> removeFavorite(SchemaObjectRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _load(prefs, _kFavorites);
    list.removeWhere((r) => r.name == ref.name && r.ambiente == ref.ambiente);
    await _save(prefs, _kFavorites, list);
  }

  Future<bool> isFavorite(SchemaObjectRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _load(prefs, _kFavorites);
    return list.any((r) => r.name == ref.name && r.ambiente == ref.ambiente);
  }

  Future<List<SchemaObjectRef>> getFavorites({String? ambiente}) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _load(prefs, _kFavorites);
    if (ambiente == null) return all;
    return all.where((r) => r.ambiente == ambiente).toList();
  }

  List<SchemaObjectRef> _load(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(SchemaObjectRef.fromJson)
          .where((r) => r.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(
    SharedPreferences prefs,
    String key,
    List<SchemaObjectRef> list,
  ) {
    return prefs.setString(
      key,
      jsonEncode(list.map((r) => r.toJson()).toList()),
    );
  }
}
