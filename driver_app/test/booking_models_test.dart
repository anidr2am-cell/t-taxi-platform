import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/l10n/app_localizations.dart';
import 'package:tride_driver/l10n/app_localizations_extensions.dart';

import 'test_fakes.dart';

void main() {
  test('parses assignment release response', () {
    final result = BookingReleaseResult.fromEnvelope({
      'success': true,
      'data': {
        'bookingNumber': 'TX209912319999',
        'released': true,
        'status': 'OPEN',
        'reasonCode': 'VEHICLE_BREAKDOWN',
      },
    });

    expect(result.released, isTrue);
    expect(result.status.code, BookingStatusCode.open);
    expect(result.reasonCode, 'VEHICLE_BREAKDOWN');
  });

  group('booking list parsing', () {
    test('parses the scheduled response envelope and contract fields', () {
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
      expect(result.items.single.vehicleType.name, '\uc138\ub2e8');
      expect(result.items.single.driverExpectedIncome.amount, 900);
      expect(
        result.items.single.assignmentStatus.code,
        AssignmentStatusCode.assigned,
      );
      expect(result.items.single.scheduledPickupAt, isNotNull);
      expect(result.items.single.standbyReferenceTimeType, 'VEHICLE_DEPARTURE');
      expect(result.items.single.standbyAllowedAt, isNotNull);
      expect(result.items.single.canConfirmStandby, isTrue);
      expect(result.items.single.standbyConfirmed, isFalse);
      expect(result.items.single.allowedActions, contains('ACCEPT_BOOKING'));
      expect(result.items.single.pickupLocation.placeId, 'pickup-place-id');
      expect(result.items.single.pickupLocation.latitude, 13.69);
      expect(result.items.single.destinationLocation.longitude, 100.5018);
      expect(result.items.single.originLongitude, 100.7501);
      expect(result.items.single.nameSignRequested, isTrue);
      expect(result.items.single.nameSignText, 'KIM FAMILY');
      expect(result.items.single.nameSignPhotoUrl, isNull);
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

  group('BookingLocation parsing', () {
    test('parses nameTh from pickupLocation payload', () {
      final location = BookingLocation.fromJson({
        'name': 'BKK - Suvarnabhumi Airport',
        'nameTh': '\u0e17\u0e48\u0e32\u0e2d\u0e32\u0e01\u0e32\u0e28\u0e22\u0e32\u0e19\u0e2a\u0e38\u0e27\u0e23\u0e23\u0e13\u0e20\u0e39\u0e21\u0e34',
        'address': '999 Nong Prue, Bang Phli',
      });

      expect(location.name, 'BKK - Suvarnabhumi Airport');
      expect(location.nameTh, '\u0e17\u0e48\u0e32\u0e2d\u0e32\u0e01\u0e32\u0e28\u0e22\u0e32\u0e19\u0e2a\u0e38\u0e27\u0e23\u0e23\u0e13\u0e20\u0e39\u0e21\u0e34');
      expect(location.address, '999 Nong Prue, Bang Phli');
    });
  });

  group('canAccept', () {
    test('uses the server standby decision and allowed time', () {
      expect(bookingSummary().canAccept, isTrue);
      expect(bookingSummary(canConfirmStandby: false).canAccept, isFalse);
      expect(bookingSummary(standbyAllowedAt: null).canAccept, isFalse);
      expect(
        bookingSummary(allowedActions: const ['VIEW_DETAILS']).canAccept,
        isFalse,
      );
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
      final l10n = AppLocalizations(const Locale('ko'));

      expect(
        detail.passengers.displayLocalized(l10n),
        '\uc131\uc778 2\uba85 \u00b7 \uc544\ub3d9 0\uba85 \u00b7 \uc720\uc544 0\uba85',
      );
      expect(
        detail.luggage.displayLocalized(l10n),
        '20\uc778\uce58 1\uac1c \u00b7 24\uc778\uce58 \uc774\uc0c1 1\uac1c \u00b7 \uace8\ud504\ubc31 0\uac1c',
      );
      expect(detail.flight.flightNumber, 'TG100');
      expect(detail.flight.latestEstimatedArrival, '2026-07-18 08:30:00');
      expect(detail.specialInstructions, 'Synthetic fixture note');
      expect(detail.nameSignRequested, isTrue);
      expect(detail.nameSignText, 'KIM FAMILY');
      expect(detail.nameSignPhotoUrl, isNull);
      expect(detail.capabilities.releaseAssignmentAvailable, isTrue);
      expect(detail.capabilities.releaseAssignmentEmergencyOnly, isFalse);
      expect(detail.capabilities.reassignmentPriority, 'NORMAL');
      expect(detail.canAccept, isTrue);
    });

    test('handles nullable optional fields without synthetic values', () {
      final l10n = AppLocalizations(const Locale('ko'));
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
          'capabilities': null,
          'nameSignRequested': null,
          'nameSignText': null,
          'nameSignPhotoUrl': null,
        },
      });

      expect(detail.summary.customerDisplayName, isNull);
      expect(detail.summary.flightNumber, isNull);
      expect(detail.passengers.displayLocalized(l10n), isNull);
      expect(detail.luggage.displayLocalized(l10n), isNull);
      expect(
        formatMoneyLocalized(l10n, detail.summary.driverExpectedIncome),
        l10n.amountUnavailable,
      );
      expect(detail.capabilities.releaseAssignmentAvailable, isFalse);
      expect(detail.capabilities.assignmentReleaseDeadline, isNull);
      expect(detail.nameSignRequested, isFalse);
      expect(detail.nameSignText, isNull);
      expect(detail.nameSignPhotoUrl, isNull);
    });

    test('handles nullable contract location and standby fields', () {
      final data = bookingJson()
        ..['acceptedAt'] = null
        ..['scheduledPickupAt'] = null
        ..['standbyReferenceTime'] = null
        ..['standbyAllowedAt'] = null
        ..['standbyConfirmedAt'] = null
        ..['pickupLocation'] = null
        ..['destinationLocation'] = null
        ..['originLatitude'] = null
        ..['originLongitude'] = null
        ..['destinationLatitude'] = null
        ..['destinationLongitude'] = null
        ..['allowedActions'] = null;

      final summary = BookingSummary.fromJson(data);

      expect(summary.acceptedAt, isNull);
      expect(summary.scheduledPickupAt, isNull);
      expect(summary.createdAt, isNull);
      expect(summary.standbyReferenceTime, isNull);
      expect(summary.standbyAllowedAt, isNull);
      expect(summary.standbyConfirmedAt, isNull);
      expect(summary.pickupLocation.name, isNull);
      expect(summary.destinationLocation.latitude, isNull);
      expect(summary.originLatitude, isNull);
      expect(summary.allowedActions, isEmpty);
      expect(summary.canAccept, isFalse);
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
    final l10n = AppLocalizations(const Locale('ko'));
    final booking = BookingSummary.fromJson(
      bookingJson(status: 'FUTURE_STATUS'),
    );
    expect(booking.status.code, BookingStatusCode.unknown);
    expect(booking.status.localizedLabel(l10n), l10n.statusUnknown);
  });

  test('formats THB like the existing driver web', () {
    final l10n = AppLocalizations(const Locale('ko'));
    expect(formatMoney(const BookingMoney(1200, 'thb')), 'THB 1,200');
    expect(formatMoney(const BookingMoney(1200.5, 'THB')), 'THB 1,200.50');
    expect(
      formatMoneyLocalized(l10n, const BookingMoney(null, 'THB')),
      l10n.amountUnavailable,
    );
  });
}
