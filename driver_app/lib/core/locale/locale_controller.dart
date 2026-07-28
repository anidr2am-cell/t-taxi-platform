import 'package:flutter/material.dart';

import 'locale_preferences.dart';

class LocaleController extends ChangeNotifier {
  LocaleController(this._preferences)
      : _locale = Locale(_normalize(_preferences.localeCode));

  final LocalePreferences _preferences;
  Locale _locale;

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    final normalized = Locale(_normalize(locale.languageCode));
    if (_locale == normalized) return;
    _locale = normalized;
    await _preferences.setLocaleCode(normalized.languageCode);
    notifyListeners();
  }

  Future<void> setLocaleCode(String code) => setLocale(Locale(code));

  static String _normalize(String code) =>
      code == 'ko' ? 'ko' : LocalePreferences.defaultLocaleCode;
}
