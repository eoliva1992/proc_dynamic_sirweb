import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-procedure draft code keyed by procId+ambiente.
abstract final class EditorDraftService {
  static String _key(String procId, String ambiente) =>
      'draft_${procId}_$ambiente';

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> _getInstance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<void> save(String procId, String ambiente, String code) async {
    final prefs = await _getInstance();
    await prefs.setString(_key(procId, ambiente), code);
  }

  static Future<String?> load(String procId, String ambiente) async {
    final prefs = await _getInstance();
    return prefs.getString(_key(procId, ambiente));
  }

  static Future<void> clear(String procId, String ambiente) async {
    final prefs = await _getInstance();
    await prefs.remove(_key(procId, ambiente));
  }
}
