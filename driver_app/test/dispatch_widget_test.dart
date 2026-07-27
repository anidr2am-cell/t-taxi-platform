import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_models.dart';
import 'package:tride_driver/features/dispatch/data/driver_socket_service.dart';
import 'package:tride_driver/features/dispatch/presentation/driver_home_shell.dart';
import 'package:tride_driver/features/dispatch/presentation/open_calls_screen.dart';

import 'test_fakes.dart';

Future<void> pumpOpenCalls(
  WidgetTester tester,
  FakeDispatchReader reader, {
  VoidCallback? onClaimed,
  DriverSocketConnection? driverSocket,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OpenCallsScreen(
        repository: reader,
        onUnauthorized: () async {},
        onClaimed: onClaimed ?? () {},
        driverSocket: driverSocket,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FakeDispatchReader onlineReader({List<OpenCall>? calls}) {
  return FakeDispatchReader()
    ..statusResult = dispatchStatus(
      online: true,
      canReceiveCalls: true,
      status: 'AVAILABLE',
    )
    ..openCallsResult = OpenCallList(
      items: calls ?? [openCall()],
      blockedReason: null,
      message: null,
    );
}

Future<void> confirmClaim(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('claimConfirmButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offline shows guidance and does not request open calls', (
    tester,
  ) async {
    final reader = FakeDispatchReader();
    final socket = FakeDriverSocketConnection();
    await pumpOpenCalls(tester, reader, driverSocket: socket);

    expect(find.text('온라인으로 전환하면 새 콜을 볼 수 있습니다'), findsOneWidget);
    expect(reader.statusCount, 1);
    expect(reader.openCallsCount, 0);
    expect(socket.connectCount, 0);
  });

  testWidgets('online toggle loads calls and offline toggle hides them', (
    tester,
  ) async {
    final reader = FakeDispatchReader()
      ..openCallsResult = OpenCallList(
        items: [openCall()],
        blockedReason: null,
        message: null,
      );
    await pumpOpenCalls(tester, reader);

    await tester.tap(find.byKey(const Key('onlineToggle')));
    await tester.pumpAndSettle();
    expect(reader.onlineCount, 1);
    expect(reader.openCallsCount, 1);
    expect(find.byKey(const Key('openCallsList')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onlineToggle')));
    await tester.pumpAndSettle();
    expect(reader.offlineCount, 1);
    expect(find.byKey(const Key('offlineOpenCallsNotice')), findsOneWidget);
  });

  testWidgets('socket call events trigger REST refresh and visual notice', (
    tester,
  ) async {
    final reader = onlineReader();
    final socket = FakeDriverSocketConnection();
    await pumpOpenCalls(tester, reader, driverSocket: socket);
    final initialLoads = reader.openCallsCount;

    socket.emit(DriverSocketEventType.newCall, {
      'bookingNumber': 'TX209912319997',
    });
    await tester.pumpAndSettle();

    expect(reader.openCallsCount, initialLoads + 1);
    expect(find.byKey(const Key('newCallSocketNotice')), findsOneWidget);

    socket.emit(DriverSocketEventType.callClaimed);
    await tester.pumpAndSettle();
    socket.emit(DriverSocketEventType.callConfirmed);
    await tester.pumpAndSettle();
    socket.emit(DriverSocketEventType.assignmentReleased, {
      'bookingNumber': 'TX209912319996',
    });
    await tester.pumpAndSettle();
    expect(reader.openCallsCount, initialLoads + 4);
  });

  testWidgets('socket reconnect forces REST refresh', (tester) async {
    final reader = onlineReader();
    final socket = FakeDriverSocketConnection();
    await pumpOpenCalls(tester, reader, driverSocket: socket);
    final initialLoads = reader.openCallsCount;

    socket.emit(DriverSocketEventType.reconnected);
    await tester.pumpAndSettle();

    expect(reader.openCallsCount, initialLoads + 1);
  });

  testWidgets('offline transition disconnects foreground socket', (
    tester,
  ) async {
    final reader = onlineReader();
    final socket = FakeDriverSocketConnection();
    await pumpOpenCalls(tester, reader, driverSocket: socket);
    expect(socket.connectCount, 1);

    await tester.tap(find.byKey(const Key('onlineToggle')));
    await tester.pumpAndSettle();

    expect(reader.offlineCount, 1);
    expect(socket.disconnectCount, 1);
    expect(socket.isConnected, isFalse);
  });

  testWidgets('background disconnects and foreground reconnects socket', (
    tester,
  ) async {
    final socket = FakeDriverSocketConnection();
    await pumpOpenCalls(tester, onlineReader(), driverSocket: socket);
    expect(socket.connectCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(socket.disconnectCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(socket.connectCount, 2);
  });

  testWidgets('online list shows airport label, time, and match badge', (
    tester,
  ) async {
    await pumpOpenCalls(tester, onlineReader());

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(find.text('Pattaya Hotel'), findsOneWidget);
    expect(find.text('2026-07-27 10:30'), findsOneWidget);
    expect(find.text('EXACT · 정확 일치'), findsOneWidget);
  });

  testWidgets('online empty list supports empty state', (tester) async {
    await pumpOpenCalls(tester, onlineReader(calls: const []));

    expect(find.byKey(const Key('openCallsEmpty')), findsOneWidget);
    expect(find.text('현재 받을 수 있는 새 콜이 없습니다.'), findsOneWidget);
  });

  testWidgets(
    'urgent call is shown above regular calls with contract details',
    (tester) async {
      final urgent = OpenCall(
        bookingNumber: 'TX209912319997',
        status: 'OPEN',
        scheduledPickupAt: '2026-07-27T10:30:00.000+07:00',
        pickupDate: '2026-07-27',
        pickupTime: '10:30',
        origin: 'BKK',
        destination: 'Pattaya Hotel',
        serviceTypeCode: 'AIRPORT_PICKUP',
        serviceTypeName: 'Airport pickup',
        vehicleTypeCode: 'SEDAN',
        vehicleTypeName: 'Sedan',
        vehicleMatchType: 'EXACT',
        isExactVehicleMatch: true,
        compatibleVehicles: [compatibleVehicle()],
        passengerCount: 2,
        amount: 1200,
        currency: 'THB',
        customerPaymentAmount: 1200,
        customerPaymentCurrency: 'THB',
        customerPaymentMethod: 'PAY_DRIVER',
        companyCommissionAmount: 300,
        companyCommissionCurrency: 'THB',
        driverExpectedIncomeAmount: 900,
        driverExpectedIncomeCurrency: 'THB',
        luggage: const OpenCallLuggage(
          carriers20Inch: 1,
          carriers24InchPlus: 0,
          golfBags: 0,
          specialItems: null,
        ),
        isUrgentRequest: true,
        negotiationId: 9,
        minRequiredEtaMinutes: 30,
      );
      await pumpOpenCalls(tester, onlineReader(calls: [urgent]));

      expect(find.byKey(const Key('urgentCallsSection')), findsOneWidget);
      expect(
        find.byKey(const Key('urgentCall-TX209912319997')),
        findsOneWidget,
      );
      expect(find.text('긴급콜'), findsOneWidget);
      expect(find.textContaining('BKK — Suvarnabhumi Airport'), findsOneWidget);
      expect(find.text('이전 거절로 30분 미만 ETA 필요'), findsOneWidget);
    },
  );

  testWidgets('pull to refresh reloads open calls', (tester) async {
    final reader = onlineReader();
    await pumpOpenCalls(tester, reader);
    final initialCount = reader.openCallsCount;

    await tester.fling(
      find.byKey(const Key('openCallsList')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(reader.openCallsCount, greaterThan(initialCount));
  });

  testWidgets('single compatible vehicle skips sheet and opens confirmation', (
    tester,
  ) async {
    await pumpOpenCalls(tester, onlineReader());

    await tester.tap(find.byKey(const Key('openCall-TX209912319998')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vehicleSelectSheet')), findsNothing);
    expect(find.byKey(const Key('claimConfirmDialog')), findsOneWidget);
    expect(find.textContaining('กข 1234'), findsOneWidget);
  });

  testWidgets('multiple compatible vehicles opens selection sheet', (
    tester,
  ) async {
    final call = openCall(
      compatibleVehicles: [
        compatibleVehicle(),
        compatibleVehicle(
          id: 22,
          code: 'VAN',
          name: 'Van',
          plate: 'V-22',
          exact: false,
        ),
      ],
    );
    await pumpOpenCalls(tester, onlineReader(calls: [call]));

    await tester.tap(find.byKey(const Key('openCall-TX209912319998')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vehicleSelectSheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('vehicleOption-22')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('claimConfirmDialog')), findsOneWidget);
    expect(find.textContaining('V-22'), findsOneWidget);
  });

  testWidgets('claim success uses selected vehicle and signals tab change', (
    tester,
  ) async {
    var claimed = false;
    final reader = onlineReader();
    await pumpOpenCalls(tester, reader, onClaimed: () => claimed = true);
    await tester.tap(find.byKey(const Key('openCall-TX209912319998')));
    await tester.pumpAndSettle();

    await confirmClaim(tester);

    expect(reader.claimCount, 1);
    expect(reader.claimedBookingNumber, 'TX209912319998');
    expect(reader.claimedVehicleId, 11);
    expect(claimed, isTrue);
    expect(find.byKey(const Key('openCall-TX209912319998')), findsNothing);
  });

  testWidgets('time conflict shows guidance and keeps call', (tester) async {
    final reader = onlineReader()
      ..claimError = const ApiException(
        ApiFailureKind.bookingTimeConflict,
        statusCode: 409,
        errorCode: 'DRIVER_BOOKING_TIME_CONFLICT',
      );
    await pumpOpenCalls(tester, reader);
    await tester.tap(find.byKey(const Key('openCall-TX209912319998')));
    await tester.pumpAndSettle();

    await confirmClaim(tester);

    expect(find.textContaining('기존 운행과 시간이 겹쳐'), findsOneWidget);
    expect(find.byKey(const Key('openCall-TX209912319998')), findsOneWidget);
  });

  testWidgets('already claimed removes call and shows guidance', (
    tester,
  ) async {
    final reader = onlineReader()
      ..claimError = const ApiException(
        ApiFailureKind.alreadyClaimed,
        statusCode: 409,
        errorCode: 'ALREADY_ASSIGNED',
      );
    await pumpOpenCalls(tester, reader);
    await tester.tap(find.byKey(const Key('openCall-TX209912319998')));
    await tester.pumpAndSettle();

    await confirmClaim(tester);

    expect(find.textContaining('다른 기사가 먼저'), findsOneWidget);
    expect(find.byKey(const Key('openCall-TX209912319998')), findsNothing);
  });

  testWidgets('home shell exposes new calls and existing trips tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHomeShell(
          bookingRepository: FakeBookingReader()
            ..listResult = bookingList(items: const []),
          dispatchRepository: FakeDispatchReader(),
          onUnauthorized: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('온라인으로 전환하면 새 콜을 볼 수 있습니다'), findsOneWidget);

    await tester.tap(find.text('내 운행'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 배정 예약'), findsOneWidget);
  });

  testWidgets('claim switches to trips and reloads an already visited list', (
    tester,
  ) async {
    final bookings = FakeBookingReader()
      ..listResult = bookingList(items: const []);
    final dispatch = onlineReader();
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHomeShell(
          bookingRepository: bookings,
          dispatchRepository: dispatch,
          onUnauthorized: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 운행'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListEmpty')), findsOneWidget);
    expect(bookings.listCount, 1);

    await tester.tap(find.text('새 콜'));
    await tester.pumpAndSettle();
    bookings.listResult = bookingList();
    await tester.tap(find.byKey(const Key('openCall-TX209912319998')));
    await tester.pumpAndSettle();
    await confirmClaim(tester);

    expect(find.text('오늘의 배정 예약'), findsOneWidget);
    expect(find.byKey(const Key('booking-TX209912319999')), findsOneWidget);
    expect(bookings.listCount, 2);
  });
}
