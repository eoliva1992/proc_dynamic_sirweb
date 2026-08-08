import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global favorites store backed by SharedPreferences.
abstract final class FavoritesService {
  static const _key = 'proc_favorites';
  static final _notifier = ValueNotifier<Set<String>>({});

  static ValueListenable<Set<String>> get listenable => _notifier;
  static Set<String> get current => _notifier.value;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _notifier.value = (prefs.getStringList(_key) ?? []).toSet();
  }

  static bool isFavorite(String id) => _notifier.value.contains(id);

  static Future<void> toggle(String id) async {
    final next = {..._notifier.value};
    if (!next.remove(id)) next.add(id);
    _notifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next.toList());
  }
}
