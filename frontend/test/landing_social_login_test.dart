import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/pages/my_bookings_page.dart';
import 'package:frontend/features/landing/widgets/landing_social_login_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('landing login section shows sign-in controls when signed out', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: const LandingSocialLoginSection(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing_social_login_section')), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.byKey(const Key('auth_login_provider_hint')), findsOneWidget);
    expect(find.byKey(const Key('landing_logout_button')), findsNothing);
  });

  testWidgets('google inline sign-in switches landing section to logged-in UI', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController(
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

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: const LandingSocialLoginSection(),
      ),
    );
    await tester.pumpAndSettle();

    await authController.completeSignInWithIdTokenForTest(
      'mock-google-id-token',
    );
    await tester.pumpAndSettle();

    expect(find.text('Minji님, 로그인되었습니다'), findsOneWidget);
    expect(find.byKey(const Key('landing_my_bookings_button')), findsOneWidget);
    expect(find.byKey(const Key('landing_logout_button')), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsNothing);
  });

  testWidgets('logout button clears session on landing login section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
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
    });

    final authController = AuthController(
      apiService: AuthApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: const LandingSocialLoginSection(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved User님, 로그인되었습니다'), findsOneWidget);

    await tester.tap(find.byKey(const Key('landing_logout_button')));
    await tester.pumpAndSettle();

    expect(authController.isLoggedIn, isFalse);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
  });

  testWidgets('my bookings button opens my bookings route', (tester) async {
    SharedPreferences.setMockInitialValues({
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
    });

    final authController = AuthController(
      apiService: AuthApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await authController.initialize();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: [
          AppLocalizationsDelegate('ko'),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routes: {
          '/my-bookings': (_) => const MyBookingsPage(),
        },
        home: AuthScope(
          controller: authController,
          child: const LandingSocialLoginSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing_my_bookings_button')));
    await tester.pumpAndSettle();

    expect(find.byType(MyBookingsPage), findsOneWidget);
  });
}
