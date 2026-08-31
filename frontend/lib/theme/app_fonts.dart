import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Multilingual font setup for customer-facing surfaces (incl. Thai/CJK labels).
abstract final class AppFonts {
  static Future<void> ensureLoaded() async {
    if (kIsWeb) {
      GoogleFonts.config.allowRuntimeFetching = true;
    }

    await GoogleFonts.pendingFonts([
      GoogleFonts.notoSans(),
      GoogleFonts.notoSansThai(),
      GoogleFonts.notoSansJp(),
      GoogleFonts.notoSansSc(),
      GoogleFonts.notoSansKr(),
    ]);
  }

  static void disableRuntimeFetchingForTests() {
    GoogleFonts.config.allowRuntimeFetching = false;
  }

  static String? get primaryFamily => GoogleFonts.notoSans().fontFamily;

  static List<String> get fallbackFamilies => [
        for (final family in [
          GoogleFonts.notoSansThai().fontFamily,
          GoogleFonts.notoSansJp().fontFamily,
          GoogleFonts.notoSansSc().fontFamily,
          GoogleFonts.notoSansKr().fontFamily,
        ])
          if (family != null) family,
        'sans-serif',
      ];

  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.notoSansTextTheme(base);

  static TextStyle languageLabel(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        );
  }
}
