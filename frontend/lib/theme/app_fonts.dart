import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bundled multilingual font families (no runtime external font CDN fetch on web).
abstract final class AppFonts {
  static const primaryFamily = 'NotoSans';
  static const thaiFamily = 'NotoSansThai';
  static const _primaryAsset = 'assets/fonts/NotoSans.ttf';
  static const _thaiAsset = 'assets/fonts/NotoSansThai.ttf';

  static const fallbackFamilies = [thaiFamily, 'sans-serif'];

  static bool _loaded = false;

  /// Ensures bundled fonts are registered with the engine before first paint.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;

    if (kIsWeb) {
      await _loadFamily(primaryFamily, _primaryAsset);
      await _loadFamily(thaiFamily, _thaiAsset);
    }

    _loaded = true;
  }

  static Future<void> _loadFamily(String family, String assetPath) async {
    final loader = FontLoader(family);
    loader.addFont(rootBundle.load(assetPath));
    await loader.load();
  }

  static void disableRuntimeFetchingForTests() {
    _loaded = true;
  }

  static TextTheme textTheme(TextTheme base) => base;

  /// Language menu labels need an explicit Thai family when the active locale
  /// is not Thai — PopupMenuItem merges parent styles, which breaks Thai glyphs on
  /// CanvasKit when the active app locale is not Thai.
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
