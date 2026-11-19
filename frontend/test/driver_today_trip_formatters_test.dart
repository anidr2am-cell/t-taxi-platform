import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_today_trip_formatters.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';

void main() {
  group('formatDriverPickupRequestTime', () {
    test(
      'formats YYYY-MM-DD and HH:mm into Thai-first pickup label and 24-hour Thai time',
      () {
        expect(
          formatDriverPickupRequestTime(
            pickupDate: '2026-07-29',
            pickupTime: '22:23',
          ),
          'เวลารับที่ลูกค้าขอ / 고객 픽업 요청 시간 29/07/2026 22:23 (เวลาไทย / 태국 시간)',
        );
      },
    );

    test('pads single-digit minutes', () {
      expect(
        formatDriverPickupRequestTime(
          pickupDate: '2026-07-01',
          pickupTime: '09:05',
        ),
        'เวลารับที่ลูกค้าขอ / 고객 픽업 요청 시간 01/07/2026 09:05 (เวลาไทย / 태국 시간)',
      );
    });

    test('falls back when date or time is malformed', () {
      expect(
        formatDriverPickupRequestTime(
          pickupDate: 'invalid',
          pickupTime: '22:23',
        ),
        'เวลารับที่ลูกค้าขอ / 고객 픽업 요청 시간 invalid 22:23',
      );
    });
  });

  group('formatDriverRoutePlaceLabel', () {
    test('shows name(nameTh) when both differ', () {
      expect(
        formatDriverRoutePlaceLabel(
          const DriverBookingLocation(
            name: 'Hilton Pattaya',
            nameTh: 'ฮิลตัน พัทยา',
            address: '333 Beach Road',
          ),
          fallbackAddress: 'Pattaya',
        ),
        'Hilton Pattaya(ฮิลตัน พัทยา)',
      );
    });

    test('shows single label when only name exists', () {
      expect(
        formatDriverRoutePlaceLabel(
          const DriverBookingLocation(name: 'Pattaya Hotel'),
          fallbackAddress: 'Pattaya',
        ),
        'Pattaya Hotel',
      );
    });

    test('shows single label when only nameTh exists', () {
      expect(
        formatDriverRoutePlaceLabel(
          const DriverBookingLocation(nameTh: 'ท่าอากาศยานสุวรรณภูมิ'),
          fallbackAddress: 'BKK',
        ),
        'ท่าอากาศยานสุวรรณภูมิ',
      );
    });

    test('uses address when names are absent', () {
      expect(
        formatDriverRoutePlaceLabel(
          const DriverBookingLocation(address: '999 Nong Prue'),
          fallbackAddress: 'BKK Airport',
        ),
        '999 Nong Prue',
      );
    });

    test('uses fallback when location is null', () {
      expect(
        formatDriverRoutePlaceLabel(null, fallbackAddress: 'BKK Airport'),
        'BKK Airport',
      );
    });
  });

  group('formatDriverRouteLineLabel', () {
    test('adds origin and destination prefixes', () {
      expect(
        formatDriverRouteLineLabel(
          prefix: '출발지',
          location: const DriverBookingLocation(name: 'Suvarnabhumi Airport'),
          fallbackAddress: 'BKK',
        ),
        '출발지 - Suvarnabhumi Airport',
      );
      expect(
        formatDriverRouteLineLabel(
          prefix: '도착지',
          location: const DriverBookingLocation(name: 'Hilton Pattaya'),
          fallbackAddress: 'Pattaya',
        ),
        '도착지 - Hilton Pattaya',
      );
    });
  });
}
