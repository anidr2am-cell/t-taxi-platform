import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/pages/kakao_oauth_callback_page.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
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

  testWidgets('callback stores tokens and restores booking complete page', (
    tester,
  ) async {
    final returnContext = SocialLoginReturnContext.fromBookingComplete(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      origin: testBookingLocation(name: 'BKK Airport'),
      destination: testBookingLocation(name: 'Pattaya'),
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await SocialLoginReturnStorage().save(returnContext);

    final authController = AuthController(
      apiService: AuthApiService(
        client: MockClient((request) async {
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
        }),
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
        home: KakaoOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/kakao/callback?code=mock-kakao-code',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'access-token');
    expect(prefs.getString(AuthTokenStorage.refreshTokenKey), 'refresh-token');
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    expect(find.text('TX202607010001'), findsOneWidget);
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
