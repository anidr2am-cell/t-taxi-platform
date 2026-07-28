import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/bookings/presentation/pickup_schedule.dart';
import 'package:tride_driver/l10n/app_localizations.dart';

void main() {
  group('pickupDelayInfo', () {
    test('returns not past when pickup is in the future', () {
      final now = DateTime(2026, 7, 18, 14, 30);
      final info = pickupDelayInfo(
        scheduledPickupAt: '2026-07-18T15:00:00+07:00',
        pickupDate: null,
        pickupTime: null,
        now: () => now,
      );

      expect(info, isNotNull);
      expect(info!.isPastPickup, isFalse);
      expect(info.delay, Duration.zero);
    });

    test('returns delay info when pickup time has passed', () {
      final now = DateTime(2026, 7, 18, 17, 0);
      final info = pickupDelayInfo(
        scheduledPickupAt: '2026-07-18T14:00:00+07:00',
        pickupDate: null,
        pickupTime: null,
        now: () => now,
      );

      expect(info, isNotNull);
      expect(info!.isPastPickup, isTrue);
      expect(info.delay, const Duration(hours: 3));
    });

    test('handles date change across midnight', () {
      final now = DateTime(2026, 7, 19, 1, 30);
      final info = pickupDelayInfo(
        scheduledPickupAt: '2026-07-18T23:30:00+07:00',
        pickupDate: null,
        pickupTime: null,
        now: () => now,
      );

      expect(info, isNotNull);
      expect(info!.isPastPickup, isTrue);
      expect(info.delay, const Duration(hours: 2));
    });

    test('falls back to pickupDate and pickupTime fields', () {
      final now = DateTime(2026, 7, 18, 15, 30);
      final info = pickupDelayInfo(
        scheduledPickupAt: null,
        pickupDate: '2026-07-18',
        pickupTime: '14:00',
        now: () => now,
      );

      expect(info, isNotNull);
      expect(info!.isPastPickup, isTrue);
      expect(info.delay, const Duration(hours: 1, minutes: 30));
    });
  });

  group('pickupDelayBannerMessage', () {
    test('returns Korean banner for delayed pickup', () {
      final l10n = AppLocalizations(const Locale('ko'));
      final message = pickupDelayBannerMessage(
        l10n,
        const PickupDelayInfo(
          isPastPickup: true,
          delay: Duration(hours: 2, minutes: 30),
        ),
      );

      expect(message, '픽업 시간 2시간 30분 경과');
    });

    test('returns Thai banner for delayed pickup', () {
      final l10n = AppLocalizations(const Locale('th'));
      final message = pickupDelayBannerMessage(
        l10n,
        const PickupDelayInfo(
          isPastPickup: true,
          delay: Duration(minutes: 45),
        ),
      );

      expect(message, 'เลยเวลารับ 45 นาที');
    });

    test('returns null when pickup is not past due', () {
      final l10n = AppLocalizations(const Locale('ko'));
      final message = pickupDelayBannerMessage(
        l10n,
        const PickupDelayInfo(isPastPickup: false, delay: Duration.zero),
      );

      expect(message, isNull);
    });
  });
}
