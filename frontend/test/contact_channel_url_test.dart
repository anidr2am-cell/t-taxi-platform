import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/contact_channel_url.dart';

void main() {
  group('contact channel URL allowlist', () {
    test('allows https URLs', () {
      final uri = parseAllowedContactChannelUrl(
        'https://line.me/R/ti/p/@example',
        allowHttp: true,
      );
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
    });

    test('allows configured messenger schemes', () {
      expect(
        parseAllowedContactChannelUrl('line://ti/p/@example', allowHttp: true),
        isNotNull,
      );
      expect(
        parseAllowedContactChannelUrl(
          'kakaotalk://plusfriend/home/_abcd',
          allowHttp: true,
        ),
        isNotNull,
      );
      expect(
        parseAllowedContactChannelUrl(
          'whatsapp://send?phone=66123456789',
          allowHttp: true,
        ),
        isNotNull,
      );
    });

    test('rejects javascript URLs', () {
      expect(
        parseAllowedContactChannelUrl('javascript:alert(1)', allowHttp: true),
        isNull,
      );
    });

    test('rejects data URLs', () {
      expect(
        parseAllowedContactChannelUrl('data:text/html,hello', allowHttp: true),
        isNull,
      );
    });

    test('rejects malformed URLs', () {
      expect(parseAllowedContactChannelUrl('not a url', allowHttp: true), isNull);
    });
  });
}
