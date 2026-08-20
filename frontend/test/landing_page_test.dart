import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_wizard_route_args.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/widgets/step_pickup_datetime.dart';
import 'package:frontend/features/booking/widgets/step_route_select.dart';
import 'package:frontend/features/booking/widgets/wizard_status_views.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/landing/models/landing_booking_draft.dart';
import 'package:frontend/features/landing/pages/customer_landing_page.dart';
import 'package:frontend/features/landing/widgets/landing_clickable_styles.dart';
import 'package:frontend/features/landing/widgets/landing_header.dart';
import 'package:frontend/features/landing/widgets/landing_hero.dart';
import 'package:frontend/features/support/pages/customer_support_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testOrigin = LocationOption(
  id: 'test:origin',
  displayName: 'Test Origin',
  kind: LocationKind.place,
);

const _testDestination = LocationOption(
  id: 'test:destination',
  displayName: 'Test Destination',
  kind: LocationKind.place,
);

Widget _wrapLanding({
  required Widget child,
  double width = 360,
  double height = 900,
  Locale locale = const Locale('en'),
}) {
  return ChangeNotifierProvider(
    key: ValueKey(locale.languageCode),
    create: (_) => LocaleState()..setLanguage(locale.languageCode),
    child: Consumer<LocaleState>(
      builder: (context, localeState, _) {
        final activeLocale = Locale(localeState.languageCode);
        return MaterialApp(
          locale: activeLocale,
          supportedLocales: AppLocalizations.supportedLanguages
              .map((code) => Locale(code))
              .toList(),
          localizationsDelegates: [
            AppLocalizationsDelegate(activeLocale.languageCode),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: {
            '/booking': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              return BookingWizardPage(
                routeArgs: args is BookingWizardRouteArgs ? args : null,
              );
            },
            '/support': (_) => const CustomerSupportPage(),
          },
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, height)),
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CustomerLandingPage', () {
    void configureView(WidgetTester tester, double width, double height) {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pumpLanding(
      WidgetTester tester, {
      double width = 360,
      double height = 900,
      Locale locale = const Locale('en'),
      LandingBookingDraft? initialDraft,
    }) async {
      configureView(tester, width, height);
      await tester.pumpWidget(
        _wrapLanding(
          width: width,
          height: height,
          locale: locale,
          child: CustomerLandingPage(initialDraft: initialDraft),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (width < 900) {
        await tester.pumpAndSettle();
      }
    }

    Future<void> pumpWizardReady(WidgetTester tester) async {
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(WizardLoadingView).evaluate().isNotEmpty) {
          continue;
        }
        if (find.byType(BookingWizardPage).evaluate().isEmpty) {
          continue;
        }
        if (find.byType(StepRouteSelect).evaluate().isNotEmpty ||
            find.byType(StepPickupDateTime).evaluate().isNotEmpty) {
          return;
        }
      }
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

    testWidgets('renders desktop booking widget at 1100px', (tester) async {
      await pumpLanding(tester, width: 1100, height: 1200);

      expect(find.byKey(const Key('landing_booking_widget')), findsOneWidget);
      expect(find.byKey(const Key('landing_booking_service_row')), findsOneWidget);
    });

    testWidgets('hides desktop booking widget below 900px', (tester) async {
      await pumpLanding(tester, width: 375, height: 900);

      expect(find.byKey(const Key('landing_booking_widget')), findsNothing);
      expect(find.text('Book now'), findsWidgets);
    });

    testWidgets('complete hero draft opens wizard at schedule step', (tester) async {
      await pumpLanding(
        tester,
        width: 1100,
        height: 1200,
        initialDraft: const LandingBookingDraft(
          serviceType: BookingServiceType.cityTransfer,
          origin: _testOrigin,
          destination: _testDestination,
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('landing_booking_submit')));
      await tester.tap(find.byKey(const Key('landing_booking_submit')));
      await pumpWizardReady(tester);

      expect(find.byType(BookingWizardPage), findsOneWidget);
      expect(find.byType(StepPickupDateTime), findsOneWidget);
      expect(find.byType(StepRouteSelect), findsNothing);
    });

    testWidgets('mobile hero CTA without draft opens wizard at route step', (
      tester,
    ) async {
      await pumpLanding(tester, width: 375);

      await tester.tap(find.text('Book now').first);
      await pumpWizardReady(tester);

      expect(find.byType(BookingWizardPage), findsOneWidget);
      expect(find.byType(StepRouteSelect), findsOneWidget);
      expect(find.byType(StepPickupDateTime), findsNothing);
    });

    testWidgets('service card selection updates shared draft state', (tester) async {
      await pumpLanding(tester, width: 1100, height: 1200);

      await tester.tap(find.byKey(const Key('landing_service_golfTransfer')));
      await pumpWizardReady(tester);
      expect(find.byType(BookingWizardPage), findsOneWidget);

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final golfHeroSegment = find.byKey(
        const Key('landing_booking_service_golfTransfer'),
      );
      final decoration = tester.widget<Ink>(
        find.descendant(of: golfHeroSegment, matching: find.byType(Ink)),
      ).decoration! as ShapeDecoration;

      expect(decoration.color, LandingClickableStyles.selectedBackground);
    });

    testWidgets('primary CTA opens booking wizard', (tester) async {
      await pumpLanding(tester);

      await tester.tap(find.text('Book now').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BookingWizardPage), findsOneWidget);
    });

    testWidgets('bottom CTA opens customer support page', (tester) async {
      await pumpLanding(tester);

      await tester.ensureVisible(find.byKey(const Key('landing_support_cta')));
      await tester.tap(find.byKey(const Key('landing_support_cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CustomerSupportPage), findsOneWidget);
      expect(
        find.text(AppLocalizations('en').t('support_title')),
        findsWidgets,
      );
    });

    testWidgets('header lookup opens lookup page', (tester) async {
      await pumpLanding(tester);

      await tester.tap(find.byIcon(Icons.search_outlined).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GuestBookingLookupPage), findsOneWidget);
    });

    testWidgets('header renders logo asset instead of text brand', (
      tester,
    ) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      final logo = tester.widget<Image>(
        find.byKey(const Key('landing_header_logo')),
      );
      final logoSize = tester.getSize(
        find.byKey(const Key('landing_header_logo')),
      );

      expect((logo.image as AssetImage).assetName, LandingHeader.logoAssetPath);
      expect(logo.fit, BoxFit.contain);
      expect(logo.semanticLabel, 'T-Rider');
      expect(logoSize.height, inInclusiveRange(30, 36));
      expect(logoSize.width, lessThanOrEqualTo(116));
      expect(
        find.descendant(
          of: find.byKey(const Key('landing_brand_block')),
          matching: find.text('T-Rider'),
        ),
        findsNothing,
      );
      expect(
        find.text(AppLocalizations('ko').t('app_subtitle')),
        findsOneWidget,
      );
    });

    testWidgets('header keeps localized subtitle when language changes', (
      tester,
    ) async {
      await pumpLanding(tester, locale: const Locale('en'));

      expect(
        find.text(AppLocalizations('en').t('app_subtitle')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('landing_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizations.languageNames['ko']!).last);
      await tester.pumpAndSettle();

      expect(
        find.text(AppLocalizations('ko').t('app_subtitle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('landing_header_lookup_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('landing_language_button')), findsOneWidget);
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
      for (final code in AppLocalizations.supportedLanguages) {
        await pumpLanding(tester, locale: Locale(code));

        expect(
          find.text(AppLocalizations(code).t('landing_hero_cta')),
          findsWidgets,
          reason: 'CTA for $code',
        );
      }
    });

    testWidgets('hero title includes T-Rider across supported landing locales', (
      tester,
    ) async {
      const expected = {
        'en': 'A comfortable start in Thailand with T-Rider',
        'ko': '태국에서 만나는 편안한 출발 T-Rider',
        'zh': '在泰国，和 T-Rider 一起舒适出发',
        'ja': 'タイで始まる快適な旅 T-Rider',
        'th': 'เริ่มต้นการเดินทางในไทยอย่างสบายใจกับ T-Rider',
      };

      for (final entry in expected.entries) {
        await pumpLanding(tester, locale: Locale(entry.key));

        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('renders localized hero copy', (tester) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      expect(
        find.text(AppLocalizations('ko').t('landing_hero_cta')),
        findsWidgets,
      );
      expect(
        find.text(AppLocalizations('ko').t('landing_hero_title')),
        findsOneWidget,
      );
    });

    testWidgets('language selector shows current language', (tester) async {
      await pumpLanding(tester, locale: const Locale('ko'));

      expect(find.text(AppLocalizations.languageNames['ko']!), findsOneWidget);
    });

    testWidgets('hero uses Pattaya image with cover fit and safe fallback', (
      tester,
    ) async {
      await pumpLanding(tester);

      final hero = tester.widget<Container>(
        find.byKey(const Key('landing_hero')),
      );
      final decoration = hero.decoration! as BoxDecoration;
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('landing_hero')),
          matching: find.byType(Image),
        ),
      );

      expect(
        LandingHero.pattayaHeroAssetPath,
        'assets/images/pattaya_hero.jpg',
      );
      expect(LandingHero.hasPattayaHeroAsset, isTrue);
      expect(decoration.gradient, isNotNull);
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, LandingHero.mobileImageAlignment);
      expect(image.errorBuilder, isNotNull);
    });

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

    testWidgets('trust section shows refund and driver policy cards', (
      tester,
    ) async {
      await pumpLanding(tester, width: 1100, locale: const Locale('ko'));
      await tester.scrollUntilVisible(
        find.text('안심 취소·환불'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('안심 취소·환불'), findsOneWidget);
      expect(find.text('기사 품질 관리'), findsOneWidget);
      expect(find.textContaining('24시간 이내 위약금 없이'), findsOneWidget);
      expect(find.textContaining('즉시 배차를 정지'), findsOneWidget);
    });

    testWidgets('trust section has no overflow at 375px with five cards', (
      tester,
    ) async {
      await pumpLanding(tester, width: 375, locale: const Locale('ko'));
      await tester.scrollUntilVisible(
        find.text('기사 품질 관리'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('안심 취소·환불'), findsOneWidget);
      expect(find.text('기사 품질 관리'), findsOneWidget);
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
