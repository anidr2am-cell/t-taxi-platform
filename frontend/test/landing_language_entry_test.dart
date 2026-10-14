import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:flutter/material.dart';
import 'package:frontend/main.dart';

void main() {
  for (final code in ['ko', 'en', 'th', 'ja', 'zh']) {
    test('landing URL selects $code without affecting service query', () {
      final uri = Uri.parse(
        'https://example.test/booking?service=AIRPORT_PICKUP&lang=$code',
      );
      expect(LocaleState(entryUri: uri).languageCode, code);
      expect(uri.queryParameters['service'], 'AIRPORT_PICKUP');
    });
  }
  test('absent or unsupported language keeps Korean', () {
    expect(LocaleState().languageCode, 'ko');
    expect(
      LocaleState(
        entryUri: Uri.parse('https://example.test/booking?lang=invalid'),
      ).languageCode,
      'ko',
    );
  });
  for (final path in ['/booking/lookup', '/support', '/privacy-policy']) {
    test('localized utility link resolves $path', () {
      final settings = RouteSettings(name: '$path?lang=ja');
      final route = buildLandingUtilityRoute(settings);
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, settings.name);
    });
  }
  test('utility routing does not intercept OAuth or other app paths', () {
    for (final name in [
      '/admin?lang=en',
      '/auth/line/callback?code=qa',
      '/support',
    ]) {
      expect(buildLandingUtilityRoute(RouteSettings(name: name)), isNull);
    }
  });
}
