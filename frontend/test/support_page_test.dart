import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/support/pages/customer_support_page.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrapSupport({
  Locale locale = const Locale('ko'),
  double width = 360,
  double height = 900,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate(locale.languageCode),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, height)),
      child: const CustomerSupportPage(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomerSupportPage', () {
    testWidgets('renders support landing content without inline chat input', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_title')), findsWidgets);
      expect(find.text(l10n.t('support_page_intro')), findsOneWidget);
      expect(find.text(l10n.t('support_inquiry_button')), findsOneWidget);
      expect(find.byKey(const Key('support_message_input')), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text(l10n.t('support_faq_placeholder')), findsOneWidget);
    });

    testWidgets('inquiry button opens chat popup with guide and input', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_dialog_title')), findsOneWidget);
      expect(find.text(l10n.t('support_default_guide')), findsOneWidget);
      expect(find.byKey(const Key('support_message_input')), findsOneWidget);
      expect(find.byKey(const Key('support_attach_button')), findsOneWidget);
      expect(find.byKey(const Key('support_send_button')), findsOneWidget);
      expect(find.text(l10n.t('support_attachment_help')), findsOneWidget);
    });

    testWidgets('sending a message adds user and auto receipt bubbles', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'BKK to Pattaya 문의드립니다',
      );
      await tester.tap(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();

      expect(find.text('BKK to Pattaya 문의드립니다'), findsOneWidget);
      expect(find.text(l10n.t('support_auto_receipt')), findsOneWidget);
      final input = tester.widget<TextField>(
        find.byKey(const Key('support_message_input')),
      );
      expect(input.controller?.text, isEmpty);
    });

    testWidgets('chat popup can be closed', (tester) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_dialog_title')), findsOneWidget);

      await tester.tap(find.byKey(const Key('support_close_button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_dialog_title')), findsNothing);
      expect(find.byKey(const Key('support_message_input')), findsNothing);
    });

    testWidgets('has no overflow at common widths', (tester) async {
      for (final width in [360.0, 768.0, 1440.0]) {
        await tester.pumpWidget(_wrapSupport(width: width));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Page at $width');

        await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Popup at $width');
        expect(find.byKey(const Key('support_message_input')), findsOneWidget);

        await tester.tap(find.byKey(const Key('support_close_button')));
        await tester.pumpAndSettle();
      }
    });
  });
}
