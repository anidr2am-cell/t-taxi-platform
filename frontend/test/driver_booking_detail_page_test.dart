import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';

void main() {
  testWidgets('shows start route action when assigned', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'START_ON_ROUTE'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, '운행 시작 / เริ่มเดินทาง'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, '기사 도착 / ถึงจุดรับแล้ว'),
      findsNothing,
    );
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
          detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
          actionError: const DriverApiException('Invalid status transition'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, '기사 도착 / ถึงจุดรับแล้ว'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invalid status transition'), findsOneWidget);
  });

  testWidgets('shows mark arrived after on route', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '기사 도착 / ถึงจุดรับแล้ว'),
      findsOneWidget,
    );
  });

  testWidgets('shows complete trip after arrival', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ARRIVED',
            actions: ['COMPLETE_TRIP'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '운행 완료 / จบงาน'), findsOneWidget);
  });

  testWidgets('hides primary action for completed booking', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'COMPLETED', actions: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.widgetWithText(FilledButton, '운행 시작 / เริ่มเดินทาง'),
      findsNothing,
    );
    expect(
      find.widgetWithText(FilledButton, '기사 도착 / ถึงจุดรับแล้ว'),
      findsNothing,
    );
    expect(find.widgetWithText(FilledButton, '운행 완료 / จบงาน'), findsNothing);
  });

  testWidgets('hides primary action for no-show booking', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'NO_SHOW', actions: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '운행 시작 / เริ่มเดินทาง'),
      findsNothing,
    );
  });

  testWidgets('shows backend message on initial load failure', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detailError: const DriverApiException('Booking not found'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking not found'), findsOneWidget);
    expect(find.text('다시 시도 / ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('customer message action opens internal driver chat', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'START_ON_ROUTE'],
          ),
        ),
        chatPageBuilder: (bookingNumber) =>
            Scaffold(body: Text('chat:$bookingNumber')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('고객에게 전화 / โทรหาลูกค้า'), findsNothing);
    expect(find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'), findsOneWidget);
    expect(find.byIcon(Icons.phone), findsNothing);

    await tester.tap(
      find.widgetWithText(OutlinedButton, '고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'),
    );
    await tester.pumpAndSettle();

    expect(find.text('chat:TX202607010001'), findsOneWidget);
  });

  testWidgets('customer message action works without customer phone', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS'],
            phone: '',
          ),
        ),
        chatPageBuilder: (bookingNumber) =>
            Scaffold(body: Text('chat:$bookingNumber')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('고객에게 전화 / โทรหาลูกค้า'), findsNothing);
    expect(find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(OutlinedButton, '고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'),
    );
    await tester.pumpAndSettle();

    expect(find.text('chat:TX202607010001'), findsOneWidget);
  });
}

Widget _wrap(
  DriverApiService api, {
  Widget Function(String bookingNumber)? chatPageBuilder,
}) {
  return MaterialApp(
    home: DriverBookingDetailPage(
      bookingNumber: 'TX202607010001',
      api: api,
      chatPageBuilder: chatPageBuilder,
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

DriverBooking _booking({
  String status = 'DRIVER_ASSIGNED',
  List<String> actions = const ['VIEW_DETAILS'],
  String? phone = '+66123456789',
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
    customerPhone: phone,
    allowedActions: actions,
  );
}

class _FakeDriverApi extends DriverApiService {
  _FakeDriverApi({
    DriverBooking? detail,
    Future<DriverBooking>? detailFuture,
    this.detailError,
    this.actionError,
  }) {
    _current = detail ?? _booking();
    if (detailFuture != null) {
      _detailFuture = detailFuture;
    }
  }

  late DriverBooking _current;
  Future<DriverBooking>? _detailFuture;
  final Exception? detailError;
  final Exception? actionError;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    if (detailError != null) throw detailError!;
    if (_detailFuture != null) return _detailFuture!;
    return _current;
  }

  @override
  Future<DriverBooking> startOnRoute(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']);
    return _current;
  }

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'DRIVER_ARRIVED', actions: ['COMPLETE_TRIP']);
    return _current;
  }

  @override
  Future<DriverBooking> completeTrip(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'COMPLETED', actions: []);
    return _current;
  }
}
