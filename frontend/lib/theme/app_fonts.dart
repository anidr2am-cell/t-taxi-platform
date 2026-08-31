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
  /// is not Thai — CanvasKit does not reliably repaint fallback glyphs otherwise.
  static String? familyForLanguageLabel(String languageCode) {
    return switch (languageCode) {
      'th' => thaiFamily,
      _ => primaryFamily,
    };
  }

  static TextStyle languageLabel(
    BuildContext context, {
    required String languageCode,
  }) {
    final base = Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        );
    final family = familyForLanguageLabel(languageCode);
    return base.copyWith(
      fontFamily: family,
      fontFamilyFallback:
          languageCode == 'th' ? const [primaryFamily, 'sans-serif'] : fallbackFamilies,
    );
  }
}
