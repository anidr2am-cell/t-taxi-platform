import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/landing/pages/customer_landing_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';

Widget _wrapLanding({
  required Widget child,
  double width = 360,
  double height = 900,
  Locale locale = const Locale('en'),
}) {
  return ChangeNotifierProvider(
    create: (_) => LocaleState()..setLanguage(locale.languageCode),
    child: MaterialApp(
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
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomerLandingPage', () {
    Future<void> pumpLanding(
      WidgetTester tester, {
      double width = 360,
      double height = 900,
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        _wrapLanding(
          width: width,
          height: height,
          locale: locale,
          child: const CustomerLandingPage(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('has no overflow at 360px', (tester) async {
      await pumpLanding(tester, width: 360);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('landing_service_row')), findsOneWidget);
    });

    testWidgets('has no overflow at 768px', (tester) async {
      await pumpLanding(tester, width: 768);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has no overflow at 1440px', (tester) async {
      await pumpLanding(tester, width: 1440, height: 1200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('primary CTA opens booking wizard', (tester) async {
      await pumpLanding(tester);

      await tester.tap(find.text('Book your comfortable ride').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BookingWizardPage), findsOneWidget);
    });

    testWidgets('header lookup opens lookup page', (tester) async {
      await pumpLanding(tester);

      await tester.tap(find.byIcon(Icons.search_outlined).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GuestBookingLookupPage), findsOneWidget);
    });

    testWidgets('service tap triggers booking wizard', (tester) async {
      await pumpLanding(tester);

      await tester.tap(find.text('Airport Pickup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BookingWizardPage), findsOneWidget);
    });

    testWidgets('renders localized hero copy', (tester) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      expect(find.text('편안한 이동 예약하기'), findsWidgets);
      expect(find.text('공항 픽업'), findsOneWidget);
    });

    testWidgets('language selector shows current language', (tester) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      expect(find.text('한국어'), findsOneWidget);
    });

    for (final code in AppLocalizations.supportedLanguages) {
      testWidgets('renders without overflow for locale $code', (tester) async {
        await pumpLanding(tester, locale: Locale(code));
        expect(tester.takeException(), isNull, reason: 'Overflow for $code');
        final serviceRow = tester.widget<Row>(find.byKey(const Key('landing_service_row')));
        expect(serviceRow.children.whereType<Expanded>().length, 4);
      });
    }
  });
}
