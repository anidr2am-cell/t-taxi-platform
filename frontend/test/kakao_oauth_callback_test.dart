import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/kakao_oauth_callback_guard.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/pages/kakao_oauth_callback_page.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/services/kakao_oauth_callback_guard_storage_memory.dart';
import 'package:frontend/features/auth/services/kakao_oauth_callback_url_stub.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
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

  test('buildKakaoOAuthCallbackRoute matches callback path', () {
    final route = buildKakaoOAuthCallbackRoute(
      RouteSettings(
        name: 'https://trider.taxi/auth/kakao/callback?code=abc',
      ),
    );

    expect(route, isNotNull);
  });

  test('buildKakaoCallbackUriWithoutCode removes code query parameter', () {
    final uri = Uri.parse(
      'https://trider.taxi/auth/kakao/callback?code=abc123&state=xyz',
    );

    expect(
      buildKakaoCallbackUriWithoutCode(uri).toString(),
      'https://trider.taxi/auth/kakao/callback?state=xyz',
    );
  });

  test('MemoryKakaoOAuthCallbackGuardStorage round-trips guard record', () async {
    final storage = MemoryKakaoOAuthCallbackGuardStorage();
    const context = SocialLoginReturnContext(
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
      result: BookingCreateResult(
        bookingNumber: 'TX202607010001',
        status: 'PENDING',
        paymentMethod: 'PAY_DRIVER',
        paymentStatus: 'UNPAID',
        totalAmount: 1500,
        currency: 'THB',
        guestAccessToken: 'guest-token',
        boardingQrToken: 'boarding-token',
        trustMessage: 'Booking received',
      ),
      serviceLabel: 'Airport Pickup',
    );

    await storage.save(
      const KakaoOAuthCallbackGuardRecord(
        code: 'mock-kakao-code',
        outcome: KakaoOAuthCallbackOutcome.failure,
        returnContext: context,
      ),
    );

    final loaded = await storage.load();
    expect(loaded?.code, 'mock-kakao-code');
    expect(loaded?.outcome, KakaoOAuthCallbackOutcome.failure);
    expect(loaded?.returnContext?.serviceLabel, 'Airport Pickup');
  });

  testWidgets('callback stores tokens and restores booking complete page', (
    tester,
  ) async {
    final guardStorage = MemoryKakaoOAuthCallbackGuardStorage();
    final returnContext = SocialLoginReturnContext.fromBookingComplete(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      origin: testBookingLocation(name: 'BKK Airport'),
      destination: testBookingLocation(name: 'Pattaya'),
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await SocialLoginReturnStorage().save(returnContext);

    final authController = _buildAuthController(
      onRequest: (request) async {
        expect(request.url.path, '/api/v1/auth/social/kakao');
        expect(
          jsonDecode(request.body) as Map<String, dynamic>,
          {
            'code': 'mock-kakao-code',
            'redirectUri': 'https://trider.taxi/auth/kakao/callback',
          },
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
                'email': 'kakao@example.com',
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
      },
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: KakaoOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/kakao/callback?code=mock-kakao-code',
          ),
          guardStorage: guardStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'access-token');
    expect(prefs.getString(AuthTokenStorage.refreshTokenKey), 'refresh-token');
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    expect(find.text('TX202607010001'), findsOneWidget);

    final stored = await guardStorage.load();
    expect(stored?.code, 'mock-kakao-code');
    expect(stored?.outcome, KakaoOAuthCallbackOutcome.success);
  });

  testWidgets('replayed callback with same code skips second API call', (
    tester,
  ) async {
    final guardStorage = MemoryKakaoOAuthCallbackGuardStorage();
    var apiCallCount = 0;
    final returnContext = SocialLoginReturnContext.fromBookingComplete(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await SocialLoginReturnStorage().save(returnContext);

    final authController = _buildAuthController(
      onRequest: (request) async {
        apiCallCount += 1;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'kakao@example.com',
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
      },
    );
    await authController.initialize();

    Future<void> pumpCallbackPage() {
      return tester.pumpWidget(
        wrapBookingCompleteTestApp(
          authController: authController,
          locale: const Locale('ko'),
          includeAppLocalizations: true,
          home: KakaoOAuthCallbackPage(
            uri: Uri.parse(
              'https://trider.taxi/auth/kakao/callback?code=mock-kakao-code',
            ),
            guardStorage: guardStorage,
          ),
        ),
      );
    }

    await pumpCallbackPage();
    await tester.pumpAndSettle();
    expect(apiCallCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await pumpCallbackPage();
    await tester.pumpAndSettle();

    expect(apiCallCount, 1);
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    expect(find.text('Invalid Kakao authorization code'), findsNothing);
  });

  testWidgets('failed replay shows already processed instead of original error', (
    tester,
  ) async {
    final guardStorage = MemoryKakaoOAuthCallbackGuardStorage();
    final returnContext = SocialLoginReturnContext.fromBookingComplete(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await guardStorage.save(
      KakaoOAuthCallbackGuardRecord(
        code: 'mock-kakao-code',
        outcome: KakaoOAuthCallbackOutcome.failure,
        returnContext: returnContext,
      ),
    );

    var apiCallCount = 0;
    final authController = _buildAuthController(
      onRequest: (request) async {
        apiCallCount += 1;
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'Invalid Kakao authorization code',
            'error_code': 'AUTH_INVALID',
          }),
          401,
        );
      },
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: KakaoOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/kakao/callback?code=mock-kakao-code',
          ),
          guardStorage: guardStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(apiCallCount, 0);
    expect(find.text('Invalid Kakao authorization code'), findsNothing);
    expect(
      find.text('이미 처리된 로그인 요청입니다. 필요하면 다시 시도해 주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('callback without code replays stored guard record', (
    tester,
  ) async {
    final guardStorage = MemoryKakaoOAuthCallbackGuardStorage();
    final returnContext = SocialLoginReturnContext.fromBookingComplete(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await guardStorage.save(
      KakaoOAuthCallbackGuardRecord(
        code: 'mock-kakao-code',
        outcome: KakaoOAuthCallbackOutcome.success,
        returnContext: returnContext,
      ),
    );

    var apiCallCount = 0;
    final authController = _buildAuthController(
      onRequest: (request) async {
        apiCallCount += 1;
        throw StateError('API should not be called');
      },
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: KakaoOAuthCallbackPage(
          uri: Uri.parse('https://trider.taxi/auth/kakao/callback'),
          guardStorage: guardStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(apiCallCount, 0);
    expect(find.text('TX202607010001'), findsOneWidget);
  });
}

AuthController _buildAuthController({
  required Future<http.Response> Function(http.Request request) onRequest,
}) {
  return AuthController(
    apiService: AuthApiService(
      client: MockClient(onRequest),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: AuthTokenStorage(),
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
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
