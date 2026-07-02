import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/landing/pages/customer_landing_page.dart';
import 'package:frontend/features/landing/widgets/landing_clickable_styles.dart';
import 'package:frontend/features/landing/widgets/landing_hero.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/theme/app_tokens.dart';
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

      await tester.tap(find.text('Book now').first);
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

    testWidgets('primary CTA is localized for supported landing locales', (
      tester,
    ) async {
      const expected = {
        'en': 'Book now',
        'ko': '예약하기',
        'zh': '立即预订',
        'ja': '予約する',
        'th': 'จองเลย',
      };

      for (final entry in expected.entries) {
        await pumpLanding(tester, locale: Locale(entry.key));

        expect(
          find.text(entry.value),
          findsWidgets,
          reason: 'CTA for ${entry.key}',
        );
      }
    });

    testWidgets('renders localized hero copy', (tester) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      expect(find.text('예약하기'), findsWidgets);
      expect(
        find.text(AppLocalizations('ko').t('landing_hero_title')),
        findsOneWidget,
      );
    });

    testWidgets('language selector shows current language', (tester) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      expect(find.text(AppLocalizations.languageNames['ko']!), findsOneWidget);
    });

    testWidgets(
      'hero keeps image fallback inactive while Pattaya asset is missing',
      (tester) async {
        await pumpLanding(tester);

        final hero = tester.widget<Container>(
          find.byKey(const Key('landing_hero')),
        );
        final decoration = hero.decoration! as BoxDecoration;

        expect(
          LandingHero.pattayaHeroAssetPath,
          'assets/images/pattaya_hero.jpg',
        );
        expect(LandingHero.hasPattayaHeroAsset, isFalse);
        expect(decoration.image, isNull);
        expect(decoration.gradient, isNotNull);
      },
    );

    testWidgets(
      'language and booking lookup controls use visible clickable surfaces',
      (tester) async {
        await pumpLanding(tester);

        final language = tester.widget<Container>(
          find.byKey(const Key('landing_language_button')),
        );
        final languageDecoration = language.decoration! as BoxDecoration;
        final lookup = tester.widget<OutlinedButton>(
          find.byKey(const Key('landing_booking_lookup_button')),
        );

        expect(language.constraints?.minWidth, greaterThanOrEqualTo(44));
        expect(language.constraints?.minHeight, greaterThanOrEqualTo(44));
        expect(languageDecoration.color, LandingClickableStyles.background);
        expect(
          lookup.style?.minimumSize?.resolve({}),
          const Size(double.infinity, 48),
        );
      },
    );

    testWidgets('passive trust icons keep passive visual treatment', (
      tester,
    ) async {
      await pumpLanding(tester);

      final trustIconSurface = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.verified_user_outlined),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = trustIconSurface.decoration! as BoxDecoration;

      expect(decoration.color, AppTokens.primaryLight);
      expect(decoration.color, isNot(LandingClickableStyles.background));
    });

    for (final code in AppLocalizations.supportedLanguages) {
      testWidgets('renders without overflow for locale $code', (tester) async {
        await pumpLanding(tester, locale: Locale(code));
        expect(tester.takeException(), isNull, reason: 'Overflow for $code');
        final serviceRow = tester.widget<Row>(
          find.byKey(const Key('landing_service_row')),
        );
        expect(serviceRow.children.whereType<Expanded>().length, 4);
      });
    }
  });
}
