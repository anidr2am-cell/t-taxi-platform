import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/account/pages/account_page.dart';
import 'package:frontend/features/booking/pages/my_bookings_page.dart';
import 'package:frontend/features/landing/pages/customer_landing_page.dart';
import 'package:frontend/features/landing/widgets/landing_social_login_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AuthController> prepareAuthController({
    http.Client? client,
    Map<String, Object>? initialPrefs,
  }) async {
    if (initialPrefs != null) {
      SharedPreferences.setMockInitialValues(initialPrefs);
    }
    final controller = AuthController(
      apiService: AuthApiService(
        client: client ?? MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await controller.initialize();
    return controller;
  }

  Widget wrapLanding({
    required AuthController authController,
    Locale locale = const Locale('ko'),
  }) {
    return ChangeNotifierProvider(
      create: (_) => LocaleState()..setLanguage(locale.languageCode),
      child: AuthScope(
        controller: authController,
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
          routes: {
            '/my-bookings': (_) => const MyBookingsPage(),
            '/account': (_) => const AccountPage(),
          },
          home: const CustomerLandingPage(),
        ),
      ),
    );
  }

  testWidgets('header stays visible while landing content scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authController = await prepareAuthController();
    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_header_logo')), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_header_logo')), findsOneWidget);
  });

  Future<void> useMobileViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('signed-out auth icon opens bottom sheet with sign-in buttons', (
    tester,
  ) async {
    await useMobileViewport(tester);
    final authController = await prepareAuthController();
    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_header_auth_button')), findsOneWidget);
    expect(find.byKey(const Key('landing_social_login_section')), findsOneWidget);
    expect(find.byKey(const Key('landing_login_prompt_banner')), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsNothing);

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_auth_bottom_sheet')), findsOneWidget);
    expect(find.byKey(const Key('landing_auth_sheet_handle')), findsOneWidget);
    expect(find.byKey(const Key('landing_auth_sheet_close')), findsOneWidget);
    expect(find.text('T-Rider 로그인'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
  });

  testWidgets('signed-in auth icon opens account menu with account and bookings', (
    tester,
  ) async {
    final authController = await prepareAuthController(
      initialPrefs: {
        AuthTokenStorage.accessTokenKey: 'saved-access',
        AuthTokenStorage.refreshTokenKey: 'saved-refresh',
        AuthTokenStorage.userJsonKey: jsonEncode({
          'id': 7,
          'email': 'saved@example.com',
          'role': 'CUSTOMER',
          'name': 'Saved User',
          'phone': null,
          'locale': 'ko',
          'isActive': true,
        }),
      },
    );

    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_header_account_menu')), findsOneWidget);
    expect(find.byKey(const Key('landing_header_my_bookings_menu')), findsOneWidget);
    expect(find.byKey(const Key('landing_header_logout_menu')), findsNothing);
  });

  testWidgets('account menu account item navigates to account page', (
    tester,
  ) async {
    final authController = await prepareAuthController(
      initialPrefs: {
        AuthTokenStorage.accessTokenKey: 'saved-access',
        AuthTokenStorage.refreshTokenKey: 'saved-refresh',
        AuthTokenStorage.userJsonKey: jsonEncode({
          'id': 7,
          'email': 'saved@example.com',
          'role': 'CUSTOMER',
          'name': 'Saved User',
          'phone': null,
          'locale': 'ko',
          'isActive': true,
        }),
      },
    );

    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('landing_header_account_menu')));
    await tester.pumpAndSettle();

    expect(find.byType(AccountPage), findsOneWidget);
  });

  testWidgets('account menu my bookings item navigates to my bookings', (
    tester,
  ) async {
    final authController = await prepareAuthController(
      initialPrefs: {
        AuthTokenStorage.accessTokenKey: 'saved-access',
        AuthTokenStorage.refreshTokenKey: 'saved-refresh',
        AuthTokenStorage.userJsonKey: jsonEncode({
          'id': 7,
          'email': 'saved@example.com',
          'role': 'CUSTOMER',
          'name': 'Saved User',
          'phone': null,
          'locale': 'ko',
          'isActive': true,
        }),
      },
    );

    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('landing_header_my_bookings_menu')));
    await tester.pumpAndSettle();

    expect(find.byType(MyBookingsPage), findsOneWidget);
  });

  testWidgets('close button dismisses auth bottom sheet', (tester) async {
    await useMobileViewport(tester);
    final authController = await prepareAuthController();
    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('landing_auth_bottom_sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('landing_auth_sheet_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_auth_bottom_sheet')), findsNothing);
  });

  testWidgets('bottom sheet shows login provider hint', (
    tester,
  ) async {
    await useMobileViewport(tester);
    final authController = await prepareAuthController();
    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();

    final bottomSheet = find.byKey(const Key('landing_auth_bottom_sheet'));
    expect(bottomSheet, findsOneWidget);
    expect(
      find.descendant(
        of: bottomSheet,
        matching: find.byKey(const Key('auth_login_provider_hint')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomSheet,
        matching: find.textContaining('마일리지 적립 내역 관리'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('google sign-in from bottom sheet closes sheet and fills icon', (
    tester,
  ) async {
    await useMobileViewport(tester);
    final authController = await prepareAuthController(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/social/google')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'accessToken': 'access-token',
                'refreshToken': 'refresh-token',
                'expiresIn': 3600,
                'user': {
                  'id': 42,
                  'email': 'guest@example.com',
                  'role': 'CUSTOMER',
                  'name': 'Minji',
                  'phone': null,
                  'locale': 'ko',
                  'isActive': true,
                },
              },
            }),
            200,
          );
        }
        return http.Response('{}', 500);
      }),
    );

    await tester.pumpWidget(wrapLanding(authController: authController));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_header_auth_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_auth_bottom_sheet')), findsOneWidget);

    await authController.completeSignInWithIdTokenForTest(
      'mock-google-id-token',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_auth_bottom_sheet')), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.byKey(const Key('landing_social_login_section')), findsOneWidget);
    expect(find.text('Minji님, 로그인되었습니다'), findsOneWidget);
  });
}
