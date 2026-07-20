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
      expect(result.items.single.bookingNumber, 'TX209912319999');
      expect(result.items.single.vehicleType.name, '세단');
      expect(result.items.single.driverExpectedIncome.amount, 900);
      expect(
        result.items.single.assignmentStatus.code,
        AssignmentStatusCode.assigned,
      );
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

  group('assignmentStatus parsing', () {
    test('parses known assignment statuses', () {
      expect(
        AssignmentStatus.parse('ASSIGNED').code,
        AssignmentStatusCode.assigned,
      );
      expect(
        AssignmentStatus.parse('ACCEPTED').code,
        AssignmentStatusCode.accepted,
      );
      expect(
        AssignmentStatus.parse('REJECTED').code,
        AssignmentStatusCode.rejected,
      );
      expect(
        AssignmentStatus.parse('COMPLETED').code,
        AssignmentStatusCode.completed,
      );
      expect(
        AssignmentStatus.parse('CANCELLED').code,
        AssignmentStatusCode.cancelled,
      );
    });

    test('treats null missing empty unknown and wrong types as unknown', () {
      expect(AssignmentStatus.parse(null).code, AssignmentStatusCode.unknown);
      expect(AssignmentStatus.parse('').code, AssignmentStatusCode.unknown);
      expect(AssignmentStatus.parse('  ').code, AssignmentStatusCode.unknown);
      expect(
        AssignmentStatus.parse('FUTURE_STATUS').code,
        AssignmentStatusCode.unknown,
      );
      expect(AssignmentStatus.parse(12).code, AssignmentStatusCode.unknown);
      expect(
        bookingSummary(includeAssignmentStatus: false).assignmentStatus.code,
        AssignmentStatusCode.unknown,
      );
    });
  });

  group('canAccept', () {
    test('true only for DRIVER_ASSIGNED + ASSIGNED', () {
      expect(bookingSummary().canAccept, isTrue);
      expect(bookingSummary(assignmentStatus: 'ACCEPTED').canAccept, isFalse);
      expect(bookingSummary(assignmentStatus: null).canAccept, isFalse);
      expect(
        bookingSummary(assignmentStatus: 'FUTURE_STATUS').canAccept,
        isFalse,
      );
      expect(
        bookingSummary(
          status: 'COMPLETED',
          assignmentStatus: 'ASSIGNED',
        ).canAccept,
        isFalse,
      );
      expect(
        bookingSummary(
          status: 'CANCELLED',
          assignmentStatus: 'ASSIGNED',
        ).canAccept,
        isFalse,
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
      expect(detail.canAccept, isTrue);
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

  group('accept response parsing', () {
    test('parses first success and idempotent success', () {
      final first = BookingAcceptance.fromEnvelope(acceptanceEnvelope());
      expect(first.idempotent, isFalse);
      expect(first.assignmentStatus.isAccepted, isTrue);
      expect(first.acceptedAt, '2026-07-18T02:30:00.000Z');

      final again = BookingAcceptance.fromEnvelope(
        acceptanceEnvelope(idempotent: true),
      );
      expect(again.idempotent, isTrue);
      expect(again.assignmentStatus.isAccepted, isTrue);
    });

    test('allows null acceptedAt and ignores unknown fields', () {
      final parsed = BookingAcceptance.fromEnvelope(
        acceptanceEnvelope(acceptedAt: null),
      );
      expect(parsed.acceptedAt, isNull);
    });

    test('rejects malformed required fields', () {
      expect(
        () => BookingAcceptance.fromEnvelope({
          'success': true,
          'data': {
            'bookingNumber': 'BAD',
            'bookingStatus': 'DRIVER_ASSIGNED',
            'assignmentStatus': 'ACCEPTED',
            'acceptedAt': null,
            'idempotent': false,
          },
        }),
        throwsA(isA<ApiException>()),
      );
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
