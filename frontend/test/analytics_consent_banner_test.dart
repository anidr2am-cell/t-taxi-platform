import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/analytics/analytics_consent.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/widgets/analytics_consent_banner.dart';

Widget _wrapBanner({
  required Widget child,
  required double width,
  Locale locale = const Locale('ko'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: [
      AppLocalizationsDelegate(locale.languageCode),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ko'), Locale('en')],
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnalyticsConsentService consentService;

  setUp(() {
    consentService = AnalyticsConsentService(InMemoryAnalyticsConsentStorage());
  });

  Future<void> pumpBanner(WidgetTester tester, {required double width}) async {
    await tester.pumpWidget(
      _wrapBanner(
        width: width,
        child: AnalyticsConsentBanner(consentService: consentService),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact banner renders without overflow at 360px', (
    tester,
  ) async {
    await pumpBanner(tester, width: 360);

    expect(tester.takeException(), isNull);
    expect(find.text('쿠키 사용 안내'), findsOneWidget);
    expect(
      find.text('서비스 개선을 위해 분석 쿠키를 사용합니다. 거부해도 예약할 수 있습니다.'),
      findsOneWidget,
    );
    expect(find.text('쿠키 허용'), findsOneWidget);
    expect(find.text('거부'), findsOneWidget);
    expect(find.text('개인정보처리방침'), findsOneWidget);
  });

  testWidgets('compact banner renders without overflow at 390px', (
    tester,
  ) async {
    await pumpBanner(tester, width: 390);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact banner renders without overflow on desktop width', (
    tester,
  ) async {
    await pumpBanner(tester, width: 1100);
    expect(tester.takeException(), isNull);
    expect(find.text('쿠키 허용'), findsOneWidget);
  });

  testWidgets('deny and allow buttons use 12px text and 36px height', (
    tester,
  ) async {
    await pumpBanner(tester, width: 360);

    final denyButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '거부'),
    );
    final allowButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '쿠키 허용'),
    );

    expect(
      denyButton.style?.minimumSize?.resolve({}),
      const Size(0, AnalyticsConsentBannerLayout.buttonHeight),
    );
    expect(
      allowButton.style?.minimumSize?.resolve({}),
      const Size(0, AnalyticsConsentBannerLayout.buttonHeight),
    );
    expect(
      denyButton.style?.textStyle?.resolve({})?.fontSize,
      AnalyticsConsentBannerLayout.buttonFontSize,
    );
    expect(
      allowButton.style?.textStyle?.resolve({})?.fontSize,
      AnalyticsConsentBannerLayout.buttonFontSize,
    );
  });
}
