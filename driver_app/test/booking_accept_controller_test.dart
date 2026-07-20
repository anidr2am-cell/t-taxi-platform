import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/presentation/booking_accept_controller.dart';

import 'test_fakes.dart';

void main() {
  test('success refreshes detail and asks for list refresh', () async {
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(acceptanceEnvelope())
      ..detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.success);
    expect(outcome.refreshList, isTrue);
    expect(outcome.detail?.summary.assignmentStatus.isAccepted, isTrue);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });

  test('idempotent success is treated as success', () async {
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(
        acceptanceEnvelope(idempotent: true),
      )
      ..detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.success);
    expect(reader.acceptCount, 1);
  });

  test('duplicate in-flight accept does not start a second POST', () async {
    final completer = Completer<BookingAcceptance>();
    final reader = FakeBookingReader()..acceptCompleter = completer;
    final controller = BookingAcceptController(reader);
    final current = bookingDetail();

    final firstFuture = controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: current,
    );
    final second = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: current,
    );

    expect(second.kind, BookingAcceptOutcomeKind.uncertain);
    expect(reader.acceptCount, 1);

    completer.complete(BookingAcceptance.fromEnvelope(acceptanceEnvelope()));
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    final first = await firstFuture;
    expect(first.kind, BookingAcceptOutcomeKind.success);
    expect(reader.acceptCount, 1);
  });

  test('401 expires auth and does not keep accepting', () async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.unauthorized);
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.expireAuth, isTrue);
    expect(outcome.kind, BookingAcceptOutcomeKind.unauthorized);
  });

  test('403 keeps current detail without closing', () async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.forbidden);
    final controller = BookingAcceptController(reader);
    final current = bookingDetail();

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: current,
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.forbidden);
    expect(outcome.detail, same(current));
    expect(outcome.closeDetail, isFalse);
    expect(outcome.expireAuth, isFalse);
  });

  test('404 closes detail and refreshes list', () async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.notFound);
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.notFound);
    expect(outcome.closeDetail, isTrue);
    expect(outcome.refreshList, isTrue);
  });

  test('409 reloads detail and can become success when ACCEPTED', () async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.conflict)
      ..detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.success);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });

  test('timeout then ACCEPTED detail is success without second POST', () async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.timeout)
      ..detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.success);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });

  test('timeout then ASSIGNED detail does not auto retry POST', () async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.timeout)
      ..detailResult = bookingDetail(assignmentStatus: 'ASSIGNED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.stillAssigned);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });

  test(
    'timeout then detail failure stays uncertain without second POST',
    () async {
      final reader = FakeBookingReader()
        ..acceptError = const ApiException(ApiFailureKind.timeout)
        ..detailError = const ApiException(ApiFailureKind.unavailable);
      final controller = BookingAcceptController(reader);

      final outcome = await controller.accept(
        bookingNumber: 'TX209912319999',
        currentDetail: bookingDetail(),
      );

      expect(outcome.kind, BookingAcceptOutcomeKind.uncertain);
      expect(reader.acceptCount, 1);
      expect(reader.detailCount, 1);
    },
  );

  test('mismatched bookingNumber in 200 is not treated as success', () async {
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(
        acceptanceEnvelope(bookingNumber: 'TX209912310000'),
      )
      ..detailResult = bookingDetail(assignmentStatus: 'ASSIGNED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, isNot(BookingAcceptOutcomeKind.success));
    expect(outcome.message.contains('예약을 수락했습니다.'), isFalse);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });

  test('ASSIGNED status in 200 is not treated as success', () async {
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(
        acceptanceEnvelope(assignmentStatus: 'ASSIGNED'),
      )
      ..detailResult = bookingDetail(assignmentStatus: 'ASSIGNED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.stillAssigned);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });

  test('invalid 200 can still resolve via detail GET ACCEPTED', () async {
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(
        acceptanceEnvelope(bookingNumber: 'TX209912310000'),
      )
      ..detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    final controller = BookingAcceptController(reader);

    final outcome = await controller.accept(
      bookingNumber: 'TX209912319999',
      currentDetail: bookingDetail(),
    );

    expect(outcome.kind, BookingAcceptOutcomeKind.success);
    expect(reader.acceptCount, 1);
    expect(reader.detailCount, 1);
  });
}
