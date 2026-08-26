import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('booking complete shows Google login section when signed out', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          authController: authController,
          result: _result(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('계정을 만들면 다음 예약이 더 편해집니다'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('나중에 하기'), findsOneWidget);
  });

  testWidgets('booking complete shows Kakao login button when enabled', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingSocialLoginSection(
          authController: authController,
          showKakaoButton: true,
          kakaoReturnContext: SocialLoginReturnContext.fromBookingComplete(
            result: _result(),
            serviceLabel: 'Airport Pickup',
            baseUri: Uri.parse('https://trider.taxi/booking'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
  });

  testWidgets('booking complete shows LINE login button when enabled', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingSocialLoginSection(
          authController: authController,
          showLineButton: true,
          lineReturnContext:
              SocialLoginReturnContext.fromBookingCompleteForLine(
            result: _result(),
            serviceLabel: 'Airport Pickup',
            baseUri: Uri.parse('https://trider.taxi/booking'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LINE으로 계속하기'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
  });

  testWidgets('kakao sign-in success stores tokens via mock callback flow', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/social/kakao')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'accessToken': 'kakao-access-token',
                'refreshToken': 'kakao-refresh-token',
                'expiresIn': 3600,
                'user': {
                  'id': 99,
                  'email': 'kakao@example.com',
                  'role': 'CUSTOMER',
                  'name': 'Kakao User',
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

    await authController.completeSignInWithKakaoCodeForTest(
      code: 'mock-kakao-code',
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'kakao-access-token');
    expect(
      prefs.getString(AuthTokenStorage.refreshTokenKey),
      'kakao-refresh-token',
    );
    expect(authController.isLoggedIn, isTrue);
    expect(authController.user?.name, 'Kakao User');
  });

  testWidgets('sign-in success stores tokens and shows connected message', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/social/google');
        expect(
          jsonDecode(request.body) as Map<String, dynamic>,
          {'idToken': 'mock-google-id-token'},
        );
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
      }),
    );

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          authController: authController,
          result: _result(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await authController.completeSignInWithIdTokenForTest(
      'mock-google-id-token',
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'access-token');
    expect(prefs.getString(AuthTokenStorage.refreshTokenKey), 'refresh-token');
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsNothing);
  });

  testWidgets('already signed-in customer hides login section on load', (
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
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          authController: authController,
          result: _result(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('계정을 만들면 다음 예약이 더 편해집니다'), findsNothing);
    expect(find.text('Google로 계속하기'), findsNothing);
    expect(find.text('Saved User님, 연결되었습니다'), findsNothing);
  });
}

BookingCreateResult _result() {
  return BookingCreateResult(
    bookingNumber: 'TX202607010001',
    status: 'PENDING',
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    boardingQrToken: 'boarding-token',
    trustMessage: 'Booking received',
  );
}
