import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/utils/driver_backend_datetime.dart';

void main() {
  group('parseBackendServiceDateTime', () {
    test('parses ISO8601 Z without double-appending timezone', () {
      final parsed = parseBackendServiceDateTime('2026-07-22T20:24:03.024Z');

      expect(parsed, isNotNull);
      expect(
        parsed!.toUtc(),
        DateTime.utc(2026, 7, 22, 20, 24, 3, 24),
      );
    });

    test('parses ISO8601 explicit offset', () {
      final parsed = parseBackendServiceDateTime('2026-07-23T03:24:03+07:00');

      expect(parsed, isNotNull);
      expect(
        parsed!.toUtc(),
        DateTime.utc(2026, 7, 22, 20, 24, 3),
      );
    });

    test('parses naive MySQL datetime as Bangkok wall clock', () {
      final parsed = parseBackendServiceDateTime('2026-07-23 03:24:03.024');

      expect(parsed, isNotNull);
      expect(
        parsed!.toUtc(),
        DateTime.utc(2026, 7, 22, 20, 24, 3, 24),
      );
    });

    test('naive MySQL and matching ISO Z refer to the same instant', () {
      final mysql = parseBackendServiceDateTime('2026-07-23 03:24:03');
      final iso = parseBackendServiceDateTime('2026-07-22T20:24:03.000Z');

      expect(mysql, isNotNull);
      expect(iso, isNotNull);
      expect(mysql!.millisecondsSinceEpoch, iso!.millisecondsSinceEpoch);
    });

    test('returns null for invalid or empty input without throwing', () {
      expect(parseBackendServiceDateTime(null), isNull);
      expect(parseBackendServiceDateTime(''), isNull);
      expect(parseBackendServiceDateTime('   '), isNull);
      expect(parseBackendServiceDateTime('not-a-date'), isNull);
      expect(parseBackendServiceDateTime('2026-07-22T20:24:03.024ZZ'), isNull);
    });
  });
}
