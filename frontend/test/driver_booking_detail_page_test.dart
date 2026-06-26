import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';

void main() {
  testWidgets('shows correct action by status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'MARK_ARRIVED'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Mark arrived');
    expect(find.text('Mark arrived'), findsOneWidget);
    expect(find.text('Scan boarding QR'), findsNothing);
  });

  testWidgets('shows loading state', (tester) async {
    final completer = Completer<DriverBooking>();
    await tester.pumpWidget(
      _wrap(_FakeDriverApi(detailFuture: completer.future)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_booking());
    await tester.pumpAndSettle();
  });

  testWidgets('shows controlled backend error state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['MARK_ARRIVED'],
          ),
          actionError: const DriverApiException('Invalid status transition'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Mark arrived');
    await tester.tap(find.text('Mark arrived'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid status transition'), findsOneWidget);
  });

  testWidgets('successful arrival refreshes detail', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['MARK_ARRIVED'],
          ),
          arrived: _booking(
            status: 'DRIVER_ARRIVED',
            actions: ['SCAN_BOARDING_QR'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Mark arrived');
    await tester.tap(find.text('Mark arrived'));
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Scan boarding QR');
    expect(find.text('Scan boarding QR'), findsOneWidget);
  });

  testWidgets('successful boarding refreshes detail', (tester) async {
    final api = _FakeDriverApi(
      detail: _booking(status: 'DRIVER_ARRIVED', actions: ['SCAN_BOARDING_QR']),
      boarded: _booking(status: 'PICKED_UP', actions: ['SCAN_DROPOFF_QR']),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Scan boarding QR');
    await tester.tap(find.text('Scan boarding QR'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manualQrTokenField')),
      'boarding-token',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Scan dropoff QR');
    expect(api.lastToken, 'boarding-token');
    expect(find.text('Scan dropoff QR'), findsOneWidget);
  });

  testWidgets('successful completion shows completed state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'PICKED_UP', actions: ['SCAN_DROPOFF_QR']),
          completed: _booking(status: 'COMPLETED', actions: []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Scan dropoff QR');
    await tester.tap(find.text('Scan dropoff QR'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manualQrTokenField')),
      'dropoff-token',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Trip completed'), findsOneWidget);
  });

  testWidgets('manual token fallback is available', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ARRIVED',
            actions: ['SCAN_BOARDING_QR'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Scan boarding QR');
    await tester.tap(find.text('Scan boarding QR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manualQrTokenField')), findsOneWidget);
    expect(find.text('Boarding QR token'), findsOneWidget);
  });
}

Widget _wrap(DriverApiService api) {
  return MaterialApp(
    home: DriverBookingDetailPage(bookingNumber: 'TX202607010001', api: api),
  );
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find.byType(Scrollable),
  );
}

DriverBooking _booking({
  String status = 'DRIVER_ASSIGNED',
  List<String> actions = const ['VIEW_DETAILS'],
}) {
  return DriverBooking(
    bookingNumber: 'TX202607010001',
    status: status,
    serviceTypeName: 'Airport Pickup',
    pickupDate: '2026-07-01',
    pickupTime: '09:30',
    origin: 'BKK Airport',
    destination: 'Pattaya Hotel',
    passengerCount: 2,
    vehicleTypeName: 'SUV',
    customerDisplayName: 'Kim',
    customerPhone: '+66123456789',
    allowedActions: actions,
  );
}

class _FakeDriverApi extends DriverApiService {
  _FakeDriverApi({
    DriverBooking? detail,
    Future<DriverBooking>? detailFuture,
    this.arrived,
    this.boarded,
    this.completed,
    this.actionError,
  }) : detailFuture = detailFuture ?? Future.value(detail ?? _booking());

  final Future<DriverBooking> detailFuture;
  final DriverBooking? arrived;
  final DriverBooking? boarded;
  final DriverBooking? completed;
  final Exception? actionError;
  String? lastToken;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) => detailFuture;

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    return arrived ??
        _booking(status: 'DRIVER_ARRIVED', actions: ['SCAN_BOARDING_QR']);
  }

  @override
  Future<DriverBooking> scanBoarding(String bookingNumber, String token) async {
    lastToken = token;
    if (actionError != null) throw actionError!;
    return boarded ??
        _booking(status: 'PICKED_UP', actions: ['SCAN_DROPOFF_QR']);
  }

  @override
  Future<DriverBooking> scanDropoff(String bookingNumber, String token) async {
    lastToken = token;
    if (actionError != null) throw actionError!;
    return completed ?? _booking(status: 'COMPLETED', actions: []);
  }
}
