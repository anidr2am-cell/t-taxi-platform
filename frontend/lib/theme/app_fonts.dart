import 'package:flutter/material.dart';

/// Bundled multilingual font families (no runtime google_fonts fetch on web).
abstract final class AppFonts {
  static const primaryFamily = 'NotoSans';
  static const thaiFamily = 'NotoSansThai';

  static const fallbackFamilies = [thaiFamily, 'sans-serif'];

  static Future<void> ensureLoaded() async {}

  static void disableRuntimeFetchingForTests() {}

  static TextTheme textTheme(TextTheme base) => base;

  /// Language menu labels need an explicit Thai family when the active locale
  /// is not Thai — CanvasKit + PopupMenu DefaultTextStyle merge can ignore
  /// per-item fontFamily unless [inherit] is false.
  static String? familyForLanguageLabel(String languageCode) {
    return switch (languageCode) {
      'th' => thaiFamily,
      _ => primaryFamily,
    };
  }

  /// Per-item language menu style. Does not inherit [Theme] or [DefaultTextStyle]
  /// fontFamily — PopupMenuItem merges parent styles, which breaks Thai glyphs on
  /// CanvasKit when the active app locale is not Thai.
  static TextStyle languageLabelStyle({
    required String languageCode,
    Color? color,
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    final family = familyForLanguageLabel(languageCode);
    return TextStyle(
      inherit: false,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFamily: family,
      fontFamilyFallback: languageCode == 'th'
          ? const [primaryFamily, 'sans-serif']
          : fallbackFamilies,
    );
  }

  static TextStyle languageLabel(
    BuildContext context, {
    required String languageCode,
  }) {
    return languageLabelStyle(
      languageCode: languageCode,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}
