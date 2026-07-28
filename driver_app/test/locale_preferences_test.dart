import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tride_driver/core/locale/locale_preferences.dart';
import 'package:tride_driver/l10n/app_localizations.dart';

import 'l10n_test_helpers.dart';

void main() {
  group('LocalePreferences', () {
    test('defaults to Thai when no stored locale', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localePrefs = LocalePreferences(prefs);

      expect(localePrefs.localeCode, LocalePreferences.defaultLocaleCode);
      expect(localePrefs.localeCode, 'th');
    });

    test('persists selected locale across reads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localePrefs = LocalePreferences(prefs);

      await localePrefs.setLocaleCode('ko');
      expect(localePrefs.localeCode, 'ko');

      final reloaded = LocalePreferences(prefs);
      expect(reloaded.localeCode, 'ko');
    });
  });

  group('LocaleController', () {
    test('notifies listeners when locale changes', () async {
      final controller = await createTestLocaleController(localeCode: 'th');
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setLocale(const Locale('ko'));

      expect(controller.locale.languageCode, 'ko');
      expect(notifyCount, greaterThan(0));
    });
  });

  group('AppLocalizations', () {
    test('Korean and Thai strings differ for key labels', () {
      final ko = AppLocalizations(const Locale('ko'));
      final th = AppLocalizations(const Locale('th'));

      expect(ko.login, '로그인');
      expect(th.login, 'เข้าสู่ระบบ');
      expect(ko.tabNewCalls, '새 콜');
      expect(th.tabNewCalls, 'งานใหม่');
      expect(ko.accept, '수락');
      expect(th.accept, 'รับงาน');
    });

    test('Thai is the default locale code in preferences', () {
      expect(LocalePreferences.defaultLocaleCode, 'th');
    });
  });
}
