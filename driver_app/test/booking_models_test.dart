import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';

import 'test_fakes.dart';

void main() {
  group('booking list parsing', () {
    test('parses the exact today response envelope', () {
      final result = BookingList.fromEnvelope({
        'success': true,
        'message': 'OK',
        'data': {
          'date': '2026-07-18',
          'items': [bookingJson()],
        },
      });

      expect(result.serviceDate, '2026-07-18');
      expect(result.items, hasLength(1));
      expect(result.items.single.bookingNumber, 'TX202607180001');
      expect(result.items.single.vehicleType.name, '세단');
      expect(result.items.single.driverExpectedIncome.amount, 900);
    });

    test('rejects an invalid service date', () {
      expect(
        () => BookingList.fromEnvelope({
          'success': true,
          'data': {'date': '2026-02-31', 'items': <Object>[]},
        }),
        throwsA(isA<ApiException>()),
      );
    });

    test('rejects malformed response envelope', () {
      expect(
        () => BookingList.fromEnvelope({
          'success': true,
          'data': {'date': '2026-07-18', 'items': 'not-a-list'},
        }),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    });
  });

  group('booking detail parsing', () {
    test('parses detail-only passenger, luggage, flight, and note fields', () {
      final detail = bookingDetail();

      expect(detail.passengers.display, '성인 2명 · 아동 0명 · 유아 0명');
      expect(detail.luggage.display, '20인치 1개 · 24인치 이상 1개 · 골프백 0개');
      expect(detail.flight.flightNumber, 'TG100');
      expect(detail.flight.latestEstimatedArrival, '2026-07-18 08:30:00');
      expect(detail.specialInstructions, 'Synthetic fixture note');
    });

    test('handles nullable optional fields without synthetic values', () {
      final data = bookingJson()
        ..['customerDisplayName'] = null
        ..['flightNumber'] = null
        ..['driverExpectedIncomeAmount'] = null
        ..['driverExpectedIncomeCurrency'] = null;
      final detail = BookingDetail.fromEnvelope({
        'success': true,
        'data': {
          ...data,
          'passengers': null,
          'luggage': null,
          'flight': null,
          'specialInstructions': null,
        },
      });

      expect(detail.summary.customerDisplayName, isNull);
      expect(detail.summary.flightNumber, isNull);
      expect(detail.passengers.display, isNull);
      expect(detail.luggage.display, isNull);
      expect(formatMoney(detail.summary.driverExpectedIncome), '금액 정보 없음');
    });
  });

  test('unknown status has a crash-safe label', () {
    final booking = BookingSummary.fromJson(
      bookingJson(status: 'FUTURE_STATUS'),
    );
    expect(booking.status.code, BookingStatusCode.unknown);
    expect(booking.status.label, '알 수 없는 상태');
  });

  test('formats THB like the existing driver web', () {
    expect(formatMoney(const BookingMoney(1200, 'thb')), 'THB 1,200');
    expect(formatMoney(const BookingMoney(1200.5, 'THB')), 'THB 1,200.50');
    expect(formatMoney(const BookingMoney(null, 'THB')), '금액 정보 없음');
  });
}
