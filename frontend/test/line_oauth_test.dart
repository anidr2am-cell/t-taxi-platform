import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/config/line_auth_config.dart';
import 'package:frontend/features/auth/models/line_oauth_callback_guard.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';

void main() {
  test('parseLineAuthorizationCode extracts code from callback URI', () {
    final uri = Uri.parse(
      'https://trider.taxi/auth/line/callback?code=abc123&state=xyz',
    );

    expect(parseLineAuthorizationCode(uri), 'abc123');
    expect(parseLineAuthorizationState(uri), 'xyz');
    expect(parseLineAuthorizationError(uri), isNull);
  });

  test('parseLineAuthorizationError extracts oauth error', () {
    final uri = Uri.parse(
      'https://trider.taxi/auth/line/callback?error=access_denied',
    );

    expect(parseLineAuthorizationCode(uri), isNull);
    expect(parseLineAuthorizationError(uri), 'access_denied');
  });

  test('buildRedirectUri uses current origin', () {
    expect(
      LineAuthConfig.buildRedirectUri(
        base: Uri.parse('https://trider.taxi/booking'),
      ),
      'https://trider.taxi/auth/line/callback',
    );
  });

  test('buildAuthorizationUri includes required LINE OAuth params', () {
    final uri = LineAuthConfig.buildAuthorizationUri(
      redirectUri: 'https://trider.taxi/auth/line/callback',
      state: 'csrf-state-token',
    );

    expect(uri.host, 'access.line.me');
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['redirect_uri'],
        'https://trider.taxi/auth/line/callback');
    expect(uri.queryParameters['state'], 'csrf-state-token');
    expect(uri.queryParameters['scope'], 'openid profile email');
    expect(uri.queryParameters['bot_prompt'], 'aggressive');
  });

  test('SocialLoginReturnContext.fromBookingCompleteForLine uses LINE redirect',
      () {
    final context = SocialLoginReturnContext.fromBookingCompleteForLine(
      result: const BookingCreateResult(
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
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );

    expect(
      context.redirectUri,
      'https://trider.taxi/auth/line/callback',
    );
  });
}
