import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/landing/pages/customer_landing_page.dart';
import 'package:frontend/features/landing/services/home_banner_api_service.dart';
import 'package:frontend/features/landing/widgets/landing_hero.dart';
import 'package:frontend/features/landing/widgets/landing_hero_carousel.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHomeBannerApiService extends HomeBannerApiService {
  _FakeHomeBannerApiService(this.banners);

  final List<HomeBannerItem> banners;

  @override
  Future<List<HomeBannerItem>> listActiveBanners() async => banners;
}

Future<AuthController> _landingAuthController() async {
  final controller = AuthController(
    apiService: AuthApiService(
      client: MockClient((_) async => http.Response('{}', 500)),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: AuthTokenStorage(),
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
  );
  await controller.initialize();
  return controller;
}

Widget _wrapLanding({
  required AuthController authController,
  required Widget child,
}) {
  return ChangeNotifierProvider(
    create: (_) => LocaleState()..setLanguage('en'),
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: [
        AppLocalizationsDelegate('en'),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      routes: {
        '/booking': (_) => const BookingWizardPage(),
      },
      home: AuthScope(
        controller: authController,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('banner slide tap opens booking wizard', (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final authController = await _landingAuthController();

    await tester.pumpWidget(
      _wrapLanding(
        authController: authController,
        child: LandingHeroCarousel(
          onBook: () {
            Navigator.of(tester.element(find.byType(LandingHeroCarousel)))
                .pushNamed('/booking');
          },
          initialBanners: const [
            HomeBannerItem(
              id: 1,
              displayOrder: 0,
              imageUrl: '/api/v1/public/home-banners/1/image',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_promo_banner_1')));
    await tester.pumpAndSettle();

    expect(find.byType(BookingWizardPage), findsOneWidget);
  });

  testWidgets('customer landing keeps hero on first carousel slide', (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final authController = await _landingAuthController();
    await tester.pumpWidget(
      _wrapLanding(
        authController: authController,
        child: CustomerLandingPage(
          homeBannerApiService: _FakeHomeBannerApiService(const []),
          initialHomeBanners: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_hero_carousel')), findsOneWidget);
    expect(find.byKey(const Key('landing_hero')), findsOneWidget);
    expect(find.text('Book now'), findsWidgets);
  });
}
