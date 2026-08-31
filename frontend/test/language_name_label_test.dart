import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_fonts.dart';
import 'package:frontend/widgets/language_name_label.dart';

void main() {
  group('LanguageNameLabel', () {
    testWidgets('Thai label keeps NotoSansThai under non-Thai DefaultTextStyle', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DefaultTextStyle(
            style: TextStyle(fontFamily: 'WrongInheritedFamily'),
            child: LanguageNameLabel(languageCode: 'th'),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('ไทย'));
      expect(text.style?.fontFamily, AppFonts.thaiFamily);
      expect(text.style?.inherit, isFalse);
    });

    testWidgets('Korean label keeps NotoSans under Thai DefaultTextStyle', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DefaultTextStyle(
            style: TextStyle(fontFamily: AppFonts.thaiFamily),
            child: LanguageNameLabel(languageCode: 'ko'),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('한국어'));
      expect(text.style?.fontFamily, AppFonts.primaryFamily);
      expect(text.style?.inherit, isFalse);
    });

    testWidgets('merged parent labelLarge style does not override item fontFamily', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final mergedParent = DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.labelLarge!,
                child: const LanguageNameLabel(languageCode: 'th'),
              );
              return Scaffold(body: mergedParent);
            },
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('ไทย'));
      expect(text.style?.fontFamily, AppFonts.thaiFamily);
      expect(text.style?.inherit, isFalse);
    });

    testWidgets(
      'each supported language keeps its own font under PopupMenu-style merge',
      (tester) async {
        for (final code in AppLocalizations.supportedLanguages) {
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  return DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.labelLarge!,
                    child: LanguageNameLabel(languageCode: code),
                  );
                },
              ),
            ),
          );

          final label = AppLocalizations.languageNames[code]!;
          final text = tester.widget<Text>(find.text(label));
          expect(
            text.style?.fontFamily,
            AppFonts.familyForLanguageLabel(code),
            reason: code,
          );
          expect(text.style?.inherit, isFalse, reason: code);
        }
      },
    );
  });
}
