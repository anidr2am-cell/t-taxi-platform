import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/services/device_locale_resolver.dart';

void main() {
  for (final testCase in <(Locale, String)>[
    (const Locale('ko', 'KR'), 'ko'),
    (const Locale('th', 'TH'), 'th'),
    (const Locale('en', 'US'), 'en'),
    (const Locale('ja', 'JP'), 'ja'),
    (const Locale('zh', 'CN'), 'zh-CN'),
    (const Locale('zh', 'TW'), 'zh-TW'),
    (const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'), 'zh-CN'),
    (const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 'zh-TW'),
  ]) {
    test('${testCase.$1} normalizes to ${testCase.$2}', () {
      expect(DeviceLocaleResolver.normalize(testCase.$1), testCase.$2);
    });
  }

  test('falls back to app language when platform locales are invalid', () {
    final resolver = DeviceLocaleResolver(
      primaryLocale: () => const Locale('und'),
      bindingLocale: () => null,
      platformLocales: () => const [],
    );

    expect(resolver.resolve(appLanguage: 'ko'), 'ko');
  });

  test('falls back to English when platform and app locales are invalid', () {
    final resolver = DeviceLocaleResolver(
      primaryLocale: () => null,
      bindingLocale: () => null,
      platformLocales: () => const [],
    );

    expect(resolver.resolve(appLanguage: 'und'), 'en');
  });

  test('device Thai takes precedence over app Korean', () {
    final resolver = DeviceLocaleResolver(
      primaryLocale: () => const Locale('th', 'TH'),
      bindingLocale: () => const Locale('ko', 'KR'),
      platformLocales: () => const [Locale('en', 'US')],
    );

    expect(resolver.resolve(appLanguage: 'ko'), 'th');
  });

  test('uses first valid locale from platform locale list', () {
    final resolver = DeviceLocaleResolver(
      primaryLocale: () => const Locale('und'),
      bindingLocale: () => const Locale('und'),
      platformLocales: () => const [Locale('und'), Locale('ja', 'JP')],
    );

    expect(resolver.resolve(appLanguage: 'ko'), 'ja');
  });
}
