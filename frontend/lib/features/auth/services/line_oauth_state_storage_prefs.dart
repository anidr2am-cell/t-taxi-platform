import 'package:shared_preferences/shared_preferences.dart';

import '../models/line_oauth_state_storage.dart';

class SharedPreferencesLineOAuthStateStorage implements LineOAuthStateStorage {
  @override
  Future<void> save(String state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LineOAuthStateStorage.storageKey, state);
  }

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(LineOAuthStateStorage.storageKey)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<String?> loadAndClear() async {
    final value = await load();
    await clear();
    return value;
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(LineOAuthStateStorage.storageKey);
  }
}
