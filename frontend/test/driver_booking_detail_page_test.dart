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

    expect(find.widgetWithText(FilledButton, 'Mark arrived'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Scan boarding QR'), findsNothing);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Mark arrived'));
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

    await tester.tap(find.widgetWithText(FilledButton, 'Mark arrived'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Scan boarding QR'), findsOneWidget);
  });

  testWidgets('successful boarding refreshes detail', (tester) async {
    final api = _FakeDriverApi(
      detail: _booking(status: 'DRIVER_ARRIVED', actions: ['SCAN_BOARDING_QR']),
      boarded: _booking(status: 'PICKED_UP', actions: ['SCAN_DROPOFF_QR']),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Scan boarding QR'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manualQrTokenField')),
      'boarding-token',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(api.lastToken, 'boarding-token');
    expect(find.widgetWithText(FilledButton, 'Scan dropoff QR'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Scan dropoff QR'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manualQrTokenField')),
      'dropoff-token',
    );
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Completed'), findsWidgets);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Scan boarding QR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manualQrTokenField')), findsOneWidget);
    expect(find.text('Boarding QR token'), findsOneWidget);
    expect(find.text('Enter code manually — no camera required'), findsOneWidget);
    expect(find.text('Enter code manually'), findsWidgets);
  });

  testWidgets('invalid manual token shows error', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'DRIVER_ARRIVED', actions: ['SCAN_BOARDING_QR']),
          actionError: const DriverApiException('Invalid QR token'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Scan boarding QR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manualQrTokenField')), 'bad-token');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid QR token'), findsOneWidget);
  });
}

Widget _wrap(DriverApiService api) {
  return MaterialApp(
    home: DriverBookingDetailPage(bookingNumber: 'TX202607010001', api: api),
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
  }) {
  _current = detail ?? _booking();
    if (detailFuture != null) {
      _detailFuture = detailFuture;
    }
  }

  late DriverBooking _current;
  Future<DriverBooking>? _detailFuture;
  final DriverBooking? arrived;
  final DriverBooking? boarded;
  final DriverBooking? completed;
  final Exception? actionError;
  String? lastToken;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    if (_detailFuture != null) return _detailFuture!;
    return _current;
  }

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    _current = arrived ??
        _booking(status: 'DRIVER_ARRIVED', actions: ['SCAN_BOARDING_QR']);
    return _current;
  }

  @override
  Future<DriverBooking> scanBoarding(String bookingNumber, String token) async {
    lastToken = token;
    if (actionError != null) throw actionError!;
    _current = boarded ??
        _booking(status: 'PICKED_UP', actions: ['SCAN_DROPOFF_QR']);
    return _current;
  }

  @override
  Future<DriverBooking> scanDropoff(String bookingNumber, String token) async {
    lastToken = token;
    if (actionError != null) throw actionError!;
    _current = completed ?? _booking(status: 'COMPLETED', actions: []);
    return _current;
  }
}
