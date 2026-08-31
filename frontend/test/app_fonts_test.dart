import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_fonts.dart';

void main() {
  test('Thai language label uses bundled NotoSansThai family', () {
    expect(AppFonts.familyForLanguageLabel('th'), AppFonts.thaiFamily);
    expect(AppFonts.familyForLanguageLabel('ko'), AppFonts.primaryFamily);
  });

  test('languageLabelStyle does not inherit parent DefaultTextStyle fonts', () {
    final thaiStyle = AppFonts.languageLabelStyle(languageCode: 'th');
    final koStyle = AppFonts.languageLabelStyle(languageCode: 'ko');

    expect(thaiStyle.inherit, isFalse);
    expect(koStyle.inherit, isFalse);
    expect(thaiStyle.fontFamily, AppFonts.thaiFamily);
    expect(koStyle.fontFamily, AppFonts.primaryFamily);
  });

  test('ensureLoaded is idempotent for tests', () async {
    AppFonts.disableRuntimeFetchingForTests();
    await AppFonts.ensureLoaded();
    await AppFonts.ensureLoaded();
  });
}
