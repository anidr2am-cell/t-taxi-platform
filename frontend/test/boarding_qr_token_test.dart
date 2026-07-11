import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/boarding_qr_token.dart';

void main() {
  group('normalizeBoardingQrToken', () {
    test('trims whitespace from raw token', () {
      expect(normalizeBoardingQrToken('  abc-token  '), 'abc-token');
    });

    test('extracts token from query parameter', () {
      expect(
        normalizeBoardingQrToken(
          'https://example.com/boarding?token=qr-token-value',
        ),
        'qr-token-value',
      );
    });

    test('extracts token from final URL path segment', () {
      expect(
        normalizeBoardingQrToken('https://example.com/boarding/segment-token'),
        'segment-token',
      );
    });
  });

  group('isBoardingQrTokenExpired', () {
    test('returns false for future expiry', () {
      expect(
        isBoardingQrTokenExpired(
          '2099-01-01 00:00:00',
          now: DateTime.utc(2026, 7, 1),
        ),
        isFalse,
      );
    });

    test('returns true for past expiry', () {
      expect(
        isBoardingQrTokenExpired(
          '2020-01-01 00:00:00',
          now: DateTime.utc(2026, 7, 1),
        ),
        isTrue,
      );
    });
  });
}
