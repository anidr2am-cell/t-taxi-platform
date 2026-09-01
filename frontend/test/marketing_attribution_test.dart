import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/analytics/analytics_consent.dart';
import 'package:frontend/core/analytics/marketing_attribution.dart';

void main() {
  group('MarketingAttributionSanitizer', () {
    test('rejects email-like utm values', () {
      expect(
        MarketingAttributionSanitizer.utmValue('user@example.com'),
        isNull,
      );
    });

    test('landing path excludes query and fragment', () {
      expect(
        MarketingAttributionSanitizer.landingPath(
          Uri.parse('https://trider.taxi/booking?utm_source=x#frag'),
        ),
        '/booking',
      );
    });
  });

  group('MarketingAttributionService TTL', () {
    late InMemoryMarketingAttributionStorage storage;
    late MarketingAttributionService service;

    setUp(() {
      storage = InMemoryMarketingAttributionStorage();
      service = MarketingAttributionService(storage);
    });

    test('expires stored touch after TTL', () {
      final now = DateTime.utc(2026, 1, 1);
      service.applySnapshot(
        MarketingAttributionSnapshot(
          firstTouch: MarketingTouch(
            source: 'google',
            medium: 'cpc',
            capturedAt: now.toIso8601String(),
            expiresAt: now.add(const Duration(days: 90)).toIso8601String(),
          ),
        ),
        now: now,
      );

      final expiredRead = service.readSnapshot(
        now: now.add(const Duration(days: 91)),
      );
      expect(expiredRead.firstTouch, isNull);
      expect(storage.read(MarketingAttributionService.firstTouchKey), isNull);
    });
  });

  group('MarketingAttributionCoordinator consent', () {
    late InMemoryMarketingAttributionStorage storage;
    late MarketingAttributionCoordinator coordinator;

    setUp(() {
      storage = InMemoryMarketingAttributionStorage();
      coordinator = MarketingAttributionCoordinator(
        service: MarketingAttributionService(storage),
      );
    });

    test('unknown consent keeps pending in memory only', () {
      coordinator.captureLanding(
        uri: Uri.parse(
          'https://trider.taxi/?utm_source=naver_blog&utm_medium=organic',
        ),
        analyticsGranted: false,
        analyticsDenied: false,
      );

      expect(storage.read(MarketingAttributionService.firstTouchKey), isNull);
      expect(coordinator.snapshotForBooking()?.firstTouch?.source, isNull);
    });

    test('grant persists pending snapshot with TTL fields', () {
      coordinator.captureLanding(
        uri: Uri.parse(
          'https://trider.taxi/booking?utm_source=naver_blog&utm_medium=organic',
        ),
        analyticsGranted: false,
        analyticsDenied: false,
        now: DateTime.utc(2026, 9, 2),
      );
      coordinator.onAnalyticsGranted(now: DateTime.utc(2026, 9, 2));

      final snapshot = coordinator.snapshotForBooking(
        now: DateTime.utc(2026, 9, 2),
      );
      expect(snapshot?.firstTouch?.source, 'naver_blog');
      expect(snapshot?.firstTouch?.expiresAt, isNotEmpty);
      expect(storage.read(MarketingAttributionService.firstTouchKey), isNotNull);
    });

    test('deny clears storage and blocks booking snapshot', () {
      coordinator.captureLanding(
        uri: Uri.parse('https://trider.taxi/?utm_source=google&utm_medium=cpc'),
        analyticsGranted: true,
        analyticsDenied: false,
      );
      coordinator.onAnalyticsDenied();

      expect(storage.read(MarketingAttributionService.firstTouchKey), isNull);
      expect(coordinator.snapshotForBooking(), isNull);
    });

    test('last touch updates without overwriting first touch', () {
      coordinator.captureLanding(
        uri: Uri.parse('https://trider.taxi/?utm_source=naver_blog&utm_medium=organic'),
        analyticsGranted: true,
        analyticsDenied: false,
        now: DateTime.utc(2026, 9, 2),
      );
      coordinator.captureLanding(
        uri: Uri.parse('https://trider.taxi/?utm_source=facebook&utm_medium=paid'),
        analyticsGranted: true,
        analyticsDenied: false,
        now: DateTime.utc(2026, 9, 3),
      );

      final snapshot = coordinator.snapshotForBooking(
        now: DateTime.utc(2026, 9, 3),
      );
      expect(snapshot?.firstTouch?.source, 'naver_blog');
      expect(snapshot?.lastTouch?.source, 'facebook');
    });
  });
}
