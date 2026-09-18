import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bulk_backup_item.dart';

class BulkBackupSelectionList {
  final String name;
  final DateTime savedAt;
  final String savedFromAmbiente;
  final List<BulkBackupItem> items;
  final BulkBackupConfig config;

  BulkBackupSelectionList({
    required this.name,
    required this.savedAt,
    required this.savedFromAmbiente,
    required Iterable<BulkBackupItem> items,
    required this.config,
  }) : items = _dedupe(items);

  Map<String, dynamic> toJson() => {
    'format': BulkBackupSelectionService.format,
    'version': BulkBackupSelectionService.version,
    'name': name,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'savedFromAmbiente': savedFromAmbiente,
    'config': config.toJson(),
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory BulkBackupSelectionList.fromJson(Map<String, dynamic> json) {
    if (json['format'] != BulkBackupSelectionService.format ||
        json['version'] != BulkBackupSelectionService.version) {
      throw const FormatException('Formato o versión de lista no soportados');
    }
    final name = json['name'];
    final savedAt = json['savedAt'];
    final ambiente = json['savedFromAmbiente'];
    final config = json['config'];
    final items = json['items'];
    if (name is! String ||
        name.trim().isEmpty ||
        savedAt is! String ||
        ambiente is! String ||
        config is! Map<String, dynamic> ||
        items is! List) {
      throw const FormatException('Lista de backup incompleta');
    }
    final parsedDate = DateTime.tryParse(savedAt);
    if (parsedDate == null) {
      throw const FormatException('Fecha de lista inválida');
    }
    return BulkBackupSelectionList(
      name: name.trim(),
      savedAt: parsedDate,
      savedFromAmbiente: ambiente,
      config: BulkBackupConfig.fromJson(config),
      items: items.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Referencia de lista inválida');
        }
        return BulkBackupItem.fromJson(item);
      }),
    );
  }

  static List<BulkBackupItem> _dedupe(Iterable<BulkBackupItem> source) {
    final result = <BulkBackupItem>[];
    final ids = <String>{};
    for (final item in source) {
      if (ids.add(item.id)) result.add(item);
    }
    return List.unmodifiable(result);
  }
}

class BulkBackupSelectionService {
  BulkBackupSelectionService({SharedPreferences? preferences}) {
    _preferences = preferences;
  }

  static const format = 'bulk-backup-selection';
  static const version = 1;
  static const _storageKey = 'bulk_backup_selection_lists_v1';
  static const _favoriteStorageKey = 'bulk_backup_favorite_items_v1';

  SharedPreferences? _preferences;

  static String encode(BulkBackupSelectionList list) =>
      jsonEncode(list.toJson());

  static BulkBackupSelectionList decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('La lista debe ser un objeto JSON');
    }
    return BulkBackupSelectionList.fromJson(decoded);
  }

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<List<BulkBackupSelectionList>> getLists() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final lists = <BulkBackupSelectionList>[];
      for (final value in decoded) {
        if (value is Map<String, dynamic>) {
          try {
            lists.add(BulkBackupSelectionList.fromJson(value));
          } on FormatException {
            continue;
          }
        }
      }
      return lists;
    } catch (_) {
      return [];
    }
  }

  Future<BulkBackupSelectionList?> getList(String name) async {
    final lists = await getLists();
    for (final list in lists) {
      if (list.name == name) return list;
    }
    return null;
  }

  Future<Set<String>> getFavoriteIds() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_favoriteStorageKey) ?? []).toSet();
  }

  Future<void> saveList(BulkBackupSelectionList list) async {
    final prefs = await _prefs;
    final lists = await getLists();
    final index = lists.indexWhere((value) => value.name == list.name);
    if (index >= 0) {
      lists[index] = list;
    } else {
      lists.add(list);
    }
    await prefs.setString(
      _storageKey,
      jsonEncode(lists.map((value) => value.toJson()).toList()),
    );
  }

  Future<void> deleteList(String name) async {
    final prefs = await _prefs;
    final lists = await getLists()
      ..removeWhere((list) => list.name == name);
    await prefs.setString(
      _storageKey,
      jsonEncode(lists.map((value) => value.toJson()).toList()),
    );
  }

  Future<void> setFavoriteItems(
    Iterable<BulkBackupItem> items, {
    required bool favorite,
  }) async {
    final prefs = await _prefs;
    final ids = await getFavoriteIds();
    for (final item in items) {
      if (favorite) {
        ids.add(item.id);
      } else {
        ids.remove(item.id);
      }
    }
    await prefs.setStringList(_favoriteStorageKey, ids.toList());
  }
}
