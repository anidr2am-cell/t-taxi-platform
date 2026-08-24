import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/config/kakao_auth_config.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseKakaoAuthorizationCode extracts code from callback URI', () {
    final uri = Uri.parse(
      'https://trider.taxi/auth/kakao/callback?code=abc123&state=xyz',
    );

    expect(parseKakaoAuthorizationCode(uri), 'abc123');
    expect(
      parseKakaoAuthorizationError(uri),
      isNull,
    );
  });

  test('parseKakaoAuthorizationError extracts oauth error', () {
    final uri = Uri.parse(
      'https://trider.taxi/auth/kakao/callback?error=access_denied',
    );

    expect(parseKakaoAuthorizationCode(uri), isNull);
    expect(parseKakaoAuthorizationError(uri), 'access_denied');
  });

  test('buildRedirectUri uses current origin', () {
    expect(
      KakaoAuthConfig.buildRedirectUri(
        base: Uri.parse('https://trider.taxi/booking'),
      ),
      'https://trider.taxi/auth/kakao/callback',
    );
  });

  test('SocialLoginReturnStorage round-trips booking complete context', () async {
    SharedPreferences.setMockInitialValues({});
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
      enableCustomerTools: true,
    );

    final storage = SocialLoginReturnStorage();
    await storage.save(context);
    final loaded = await storage.loadAndClear();

    expect(loaded, isNotNull);
    expect(loaded!.redirectUri, context.redirectUri);
    expect(loaded.result.bookingNumber, 'TX202607010001');
    expect(loaded.serviceLabel, 'Airport Pickup');
    expect(loaded.enableCustomerTools, isTrue);

    final encoded = jsonEncode(context.toJson());
    final decoded = SocialLoginReturnContext.fromJson(
      Map<String, dynamic>.from(jsonDecode(encoded) as Map),
    );
    expect(decoded.result.guestAccessToken, 'guest-token');
  });
}
