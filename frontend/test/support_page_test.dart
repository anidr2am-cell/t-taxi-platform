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
    testWidgets('renders inquiry and FAQ placeholder', (tester) async {
      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();

      expect(find.text('고객센터'), findsWidgets);
      expect(find.text('고객센터를 통한 예약 및 문의'), findsOneWidget);
      expect(
        find.text(
          '안녕하세요. T-Ride 고객센터입니다. 예약 문의, 항공편 정보, 픽업 장소, 목적지를 남겨주시면 확인 후 안내드리겠습니다.',
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(
        find.text('자주 하는 질문은 고객 문의 데이터가 축적되면 우선순위에 따라 업데이트될 예정입니다.'),
        findsOneWidget,
      );
    });

    testWidgets('sending a message adds user and auto receipt bubbles', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'BKK to Pattaya 문의드립니다',
      );
      await tester.tap(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();

      expect(find.text('BKK to Pattaya 문의드립니다'), findsOneWidget);
      expect(
        find.text('자동 접수 안내: 문의가 접수되었습니다. 고객센터에서 확인 후 안내드리겠습니다.'),
        findsOneWidget,
      );
    });

    testWidgets('has no overflow at common widths', (tester) async {
      for (final width in [360.0, 768.0, 1440.0]) {
        await tester.pumpWidget(_wrapSupport(width: width));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Overflow at $width');
        expect(find.byKey(const Key('support_message_input')), findsOneWidget);
      }
    });
  });
}
