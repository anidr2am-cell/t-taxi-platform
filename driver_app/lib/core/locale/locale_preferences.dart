import 'package:shared_preferences/shared_preferences.dart';

class LocalePreferences {
  LocalePreferences(this._prefs);

  static const storageKey = 'app_locale';
  static const defaultLocaleCode = 'th';

  final SharedPreferences _prefs;

  String get localeCode =>
      _prefs.getString(storageKey) ?? defaultLocaleCode;

  Future<void> setLocaleCode(String code) =>
      _prefs.setString(storageKey, code);

  static Future<LocalePreferences> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalePreferences(prefs);
  }
}
