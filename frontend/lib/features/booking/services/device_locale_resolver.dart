import 'dart:ui';

import 'package:flutter/widgets.dart';

typedef LocaleReader = Locale? Function();
typedef LocaleListReader = List<Locale> Function();

class DeviceLocaleResolver {
  DeviceLocaleResolver({
    LocaleReader? primaryLocale,
    LocaleReader? bindingLocale,
    LocaleListReader? platformLocales,
  }) : _primaryLocale =
           primaryLocale ?? (() => PlatformDispatcher.instance.locale),
       _bindingLocale =
           bindingLocale ??
           (() => WidgetsBinding.instance.platformDispatcher.locale),
       _platformLocales =
           platformLocales ?? (() => PlatformDispatcher.instance.locales);

  final LocaleReader _primaryLocale;
  final LocaleReader _bindingLocale;
  final LocaleListReader _platformLocales;

  String resolve({String? appLanguage}) {
    final candidates = <Locale?>[
      _primaryLocale(),
      _bindingLocale(),
      ..._platformLocales(),
    ];
    for (final locale in candidates) {
      final normalized = normalize(locale);
      if (normalized != null) return normalized;
    }
    return normalizeLanguageTag(appLanguage) ?? 'en';
  }

  static String? normalize(Locale? locale) {
    if (locale == null) return null;
    final language = locale.languageCode.trim().toLowerCase();
    if (language.isEmpty || language == 'und') return null;
    if (language != 'zh') return language;

    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    if (script == 'hant' || const {'TW', 'HK', 'MO'}.contains(country)) {
      return 'zh-TW';
    }
    if (script == 'hans' || const {'CN', 'SG'}.contains(country)) {
      return 'zh-CN';
    }
    return 'zh';
  }

  static String? normalizeLanguageTag(String? value) {
    final tag = value?.trim();
    if (tag == null || tag.isEmpty) return null;
    final parts = tag.replaceAll('_', '-').split('-');
    final language = parts.first.toLowerCase();
    if (language.isEmpty || language == 'und') return null;
    if (language != 'zh') return language;

    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4) script = part;
      if (part.length == 2 || part.length == 3) country = part;
    }
    return normalize(
      Locale.fromSubtags(
        languageCode: language,
        scriptCode: script,
        countryCode: country,
      ),
    );
  }
}
