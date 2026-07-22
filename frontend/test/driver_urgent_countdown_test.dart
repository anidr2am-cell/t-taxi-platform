import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/utils/driver_backend_datetime.dart';

void main() {
  group('remainingUntilBackendServiceDateTime', () {
    final anchor = DateTime.utc(2026, 7, 22, 20, 22, 0);

    test('mysql naive customer decision expiry is about two minutes', () {
      final remaining = remainingUntilBackendServiceDateTime(
        '2026-07-23 03:24:03',
        now: anchor,
      );

      expect(remaining.inMinutes, 2);
      expect(remaining.inSeconds, lessThan(180));
      expect(remaining.inHours, 0);
    });

    test('mysql naive lock expiry is about three minutes', () {
      final remaining = remainingUntilBackendServiceDateTime(
        '2026-07-23 03:25:03',
        now: anchor,
      );

      expect(remaining.inMinutes, 3);
      expect(remaining.inSeconds, lessThan(240));
      expect(remaining.inHours, 0);
    });

    test('correct UTC ISO Z lock expiry is about three minutes', () {
      final remaining = remainingUntilBackendServiceDateTime(
        '2026-07-22T20:25:03.000Z',
        now: anchor,
      );

      expect(remaining.inMinutes, 3);
      expect(remaining.inSeconds, lessThan(240));
      expect(remaining.inHours, 0);
    });

    test('legacy mislabeled ISO Z does not throw from remaining helper', () {
      expect(
        () => remainingUntilBackendServiceDateTime(
          '2026-07-23T03:24:03.000Z',
          now: anchor,
        ),
        returnsNormally,
      );
    });

    test('invalid expiry returns fallback without throwing', () {
      expect(
        remainingUntilBackendServiceDateTime(
          'not-a-date',
          now: anchor,
          fallback: const Duration(minutes: 2),
        ),
        const Duration(minutes: 2),
      );
    });
  });

  group('driver urgent countdown display', () {
    testWidgets('mysql naive expiry renders expected countdown label', (
      tester,
    ) async {
      final remaining = remainingUntilBackendServiceDateTime(
        '2026-07-23 03:24:03',
        now: DateTime.utc(2026, 7, 22, 20, 22, 0),
      );

      await tester.pumpWidget(
        MaterialApp(home: Text(formatCountdownMmSs(remaining))),
      );

      expect(find.text('02:03'), findsOneWidget);
    });

    testWidgets('legacy mislabeled ISO Z countdown helper does not throw', (
      tester,
    ) async {
      late Duration remaining;
      expect(
        () {
          remaining = remainingUntilBackendServiceDateTime(
            '2026-07-23T03:24:03.000Z',
            now: DateTime.utc(2026, 7, 22, 20, 22, 0),
          );
        },
        returnsNormally,
      );

      await tester.pumpWidget(
        MaterialApp(home: Text(formatCountdownMmSs(remaining))),
      );

      expect(find.byType(Text), findsOneWidget);
    });
  });
}
