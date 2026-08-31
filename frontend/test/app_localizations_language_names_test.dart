import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('languageNames thai label uses native Thai script codepoints', () {
    final label = AppLocalizations.languageNames['th']!;
    expect(label, 'ไทย');
    expect(label.runes.toList(), [0x0E44, 0x0E17, 0x0E22]);
  });

  test('languageNames cover all supported languages with native scripts', () {
    for (final code in AppLocalizations.supportedLanguages) {
      final label = AppLocalizations.languageNames[code];
      expect(label, isNotNull);
      expect(label!.trim(), isNotEmpty);
    }

    expect(AppLocalizations.languageNames['zh'], '中文');
    expect(AppLocalizations.languageNames['ja'], '日本語');
  });
}
