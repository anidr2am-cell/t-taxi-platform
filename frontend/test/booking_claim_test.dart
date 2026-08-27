import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';
import 'support/fake_google_sign_in_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SocialLoginReturnContext claimContext() {
    return SocialLoginReturnContext.fromBookingComplete(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      origin: testBookingLocation(name: 'BKK Airport'),
      destination: testBookingLocation(name: 'Pattaya'),
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
  }

  AuthController buildAuthController({
    required http.Client client,
    FakeGoogleSignInService? googleSignInService,
  }) {
    return AuthController(
      apiService: AuthApiService(
        client: client,
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: googleSignInService ?? FakeGoogleSignInService(),
    );
  }

  MockClient claimTrackingClient(List<Map<String, dynamic>> claimCalls) {
    return MockClient((request) async {
      if (request.url.path.endsWith('/auth/social/google')) {
        return _sessionResponse('google-access-token');
      }
      if (request.url.path.endsWith('/auth/social/kakao')) {
        return _sessionResponse('kakao-access-token');
      }
      if (request.url.path.endsWith('/auth/social/line')) {
        return _sessionResponse('line-access-token');
      }
      if (request.url.path.endsWith('/customer/bookings/claim')) {
        claimCalls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      }
      return http.Response('{}', 500);
    });
  }

  testWidgets(
    'mobile Google button registers pending claim context and calls claim API',
    (tester) async {
      final claimCalls = <Map<String, dynamic>>[];
      final googleSignInService = FakeGoogleSignInService();
      final authController = buildAuthController(
        client: claimTrackingClient(claimCalls),
        googleSignInService: googleSignInService,
      );
      await authController.initialize();

      await tester.pumpWidget(
        wrapBookingCompleteTestApp(
          authController: authController,
          locale: const Locale('ko'),
          includeAppLocalizations: true,
          home: BookingSocialLoginSection(
            authController: authController,
            claimContext: claimContext(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(authController.pendingClaimContextForTest, isNotNull);
      expect(
        authController.pendingClaimContextForTest!.result!.bookingNumber,
        'TX202607010001',
      );

      await tester.tap(find.text('Google로 계속하기'));
      await tester.pumpAndSettle();

      expect(claimCalls.length, 1);
      expect(claimCalls.single, {
        'bookingNumber': 'TX202607010001',
        'guestAccessToken': 'guest-token',
      });
      expect(authController.isLoggedIn, isTrue);
      expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    },
  );

  testWidgets(
    'web Google authentication event uses pending claim context for claim API',
    (tester) async {
      final claimCalls = <Map<String, dynamic>>[];
      final googleSignInService = FakeGoogleSignInService();
      final authController = buildAuthController(
        client: claimTrackingClient(claimCalls),
        googleSignInService: googleSignInService,
      );
      await authController.initialize();
      authController.attachGoogleAuthenticationListenerForTest();

      await tester.pumpWidget(
        wrapBookingCompleteTestApp(
          authController: authController,
          locale: const Locale('ko'),
          includeAppLocalizations: true,
          home: BookingSocialLoginSection(
            authController: authController,
            claimContext: claimContext(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      googleSignInService.emitSignIn();
      await tester.pumpAndSettle();

      expect(claimCalls.length, 1);
      expect(claimCalls.single, {
        'bookingNumber': 'TX202607010001',
        'guestAccessToken': 'guest-token',
      });
      expect(authController.isLoggedIn, isTrue);
      expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    },
  );

  test('Kakao sign-in calls claim API with booking number and guest token', () async {
    final claimCalls = <Map<String, dynamic>>[];
    final authController = buildAuthController(
      client: claimTrackingClient(claimCalls),
    );
    await authController.initialize();

    await authController.completeSignInWithKakaoCodeForTest(
      code: 'mock-kakao-code',
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
      claimContext: claimContext(),
    );

    expect(claimCalls.length, 1);
    expect(claimCalls.single['bookingNumber'], 'TX202607010001');
    expect(claimCalls.single['guestAccessToken'], 'guest-token');
    expect(authController.isLoggedIn, isTrue);
  });

  test('LINE sign-in calls claim API with booking number and guest token', () async {
    final claimCalls = <Map<String, dynamic>>[];
    final authController = buildAuthController(
      client: claimTrackingClient(claimCalls),
    );
    await authController.initialize();

    await authController.completeSignInWithLineCodeForTest(
      code: 'mock-line-code',
      redirectUri: 'https://trider.taxi/auth/line/callback',
      claimContext: SocialLoginReturnContext.fromBookingCompleteForLine(
        result: _result(),
        serviceLabel: 'Airport Pickup',
        baseUri: Uri.parse('https://trider.taxi/booking'),
      ),
    );

    expect(claimCalls.length, 1);
    expect(claimCalls.single['bookingNumber'], 'TX202607010001');
    expect(claimCalls.single['guestAccessToken'], 'guest-token');
    expect(authController.isLoggedIn, isTrue);
  });

  testWidgets('claim failure keeps connected UI after Google sign-in', (
    tester,
  ) async {
    final googleSignInService = FakeGoogleSignInService();
    final authController = AuthController(
      apiService: AuthApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/social/google')) {
            return _sessionResponse('access-token');
          }
          if (request.url.path.endsWith('/customer/bookings/claim')) {
            return http.Response(
              jsonEncode({
                'success': false,
                'error_code': 'BOOKING_ALREADY_CLAIMED',
                'message': 'Already linked',
              }),
              409,
            );
          }
          return http.Response('{}', 500);
        }),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: googleSignInService,
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingSocialLoginSection(
          authController: authController,
          claimContext: claimContext(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();

    expect(authController.isLoggedIn, isTrue);
    expect(authController.errorMessage, isNull);
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
  });

  testWidgets('dispose clears pending claim context', (tester) async {
    final authController = buildAuthController(
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: BookingSocialLoginSection(
          authController: authController,
          claimContext: claimContext(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(authController.pendingClaimContextForTest, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(authController.pendingClaimContextForTest, isNull);
  });
}

http.Response _sessionResponse(String accessToken) {
  return http.Response(
    jsonEncode({
      'success': true,
      'data': {
        'accessToken': accessToken,
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
