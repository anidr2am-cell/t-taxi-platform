import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_fonts.dart';

void main() {
  test('Thai language label uses bundled NotoSansThai family', () {
    expect(AppFonts.familyForLanguageLabel('th'), AppFonts.thaiFamily);
    expect(AppFonts.familyForLanguageLabel('ko'), AppFonts.primaryFamily);
  });
}
