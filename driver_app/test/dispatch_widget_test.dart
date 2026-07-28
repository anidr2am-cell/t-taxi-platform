import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_models.dart';
import 'package:tride_driver/features/dispatch/data/driver_socket_service.dart';
import 'package:tride_driver/features/dispatch/presentation/driver_home_shell.dart';
import 'package:tride_driver/features/dispatch/presentation/open_calls_screen.dart';

import 'test_fakes.dart';

Future<void> pumpOpenCalls(
  WidgetTester tester,
  FakeDispatchReader reader, {
  VoidCallback? onClaimed,
  VoidCallback? onOpenSettlement,
  DriverSocketConnection? driverSocket,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme:
          theme ??
          ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF006A60),
            ),
          ),
      home: OpenCallsScreen(
        repository: reader,
        onUnauthorized: () async {},
        onClaimed: onClaimed ?? () {},
        onOpenSettlement: onOpenSettlement,
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
    expect(
      find.byKey(const Key('openCallGate-TX209912319998')),
      findsOneWidget,
    );
    expect(find.text('3번 게이트'), findsOneWidget);
  });

  testWidgets('open-call gate badge hides outside BKK airport pickup', (
    tester,
  ) async {
    await pumpOpenCalls(
      tester,
      onlineReader(
        calls: [openCall(origin: 'DMK Airport', nameSignRequested: true)],
      ),
    );

    expect(find.byKey(const Key('openCallGate-TX209912319998')), findsNothing);
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
        nameSignRequested: true,
        nameSignText: 'KIM FAMILY',
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

  testWidgets('home shell exposes four tabs and pending settlement badge', (
    tester,
  ) async {
    final settlement = FakeSettlementApi()
      ..items = [
        settlementItem(bookingNumber: 'TX-DUE', commissionStatus: 'DUE'),
        settlementItem(
          bookingNumber: 'TX-BLOCKED',
          commissionStatus: 'APPROVED',
          blocksNewCalls: true,
        ),
        settlementItem(bookingNumber: 'TX-OK', commissionStatus: 'APPROVED'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHomeShell(
          bookingRepository: FakeBookingReader(),
          dispatchRepository: FakeDispatchReader(),
          accountApi: FakeAccountApi(),
          settlementApi: settlement,
          onUnauthorized: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('새 콜'), findsWidgets);
    expect(find.text('내 운행'), findsOneWidget);
    expect(find.text('정산'), findsOneWidget);
    expect(find.text('계정'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('정산'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settlementListSuccess')), findsOneWidget);
    expect(settlement.listCount, greaterThanOrEqualTo(2));
  });

  testWidgets('unpaid settlement block banner opens settlement tab', (
    tester,
  ) async {
    final dispatch = onlineReader(calls: const [])
      ..openCallsResult = const OpenCallList(
        items: [],
        blockedReason: 'UNPAID_SETTLEMENT',
        message: 'unpaid',
      );
    final settlement = FakeSettlementApi()
      ..items = [settlementItem(bookingNumber: 'TX-DUE')];
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHomeShell(
          bookingRepository: FakeBookingReader(),
          dispatchRepository: dispatch,
          accountApi: FakeAccountApi(),
          settlementApi: settlement,
          onUnauthorized: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settlementBlockedBanner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('openSettlementFromBlockedBanner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settlementListSuccess')), findsOneWidget);
  });

  testWidgets('refreshRequest change reloads status and open calls', (
    tester,
  ) async {
    final reader = onlineReader();
    await tester.pumpWidget(
      MaterialApp(home: _OpenCallsRefreshHarness(reader: reader)),
    );
    await tester.pumpAndSettle();
    expect(reader.statusCount, 1);
    expect(reader.openCallsCount, 1);

    await tester.tap(find.byKey(const Key('incrementOpenCallsRefresh')));
    await tester.pumpAndSettle();

    expect(reader.statusCount, 2);
    expect(reader.openCallsCount, 2);
  });

  testWidgets('returning to open calls tab refreshes settlement block state', (
    tester,
  ) async {
    final dispatch = onlineReader(calls: const [])
      ..openCallsResult = const OpenCallList(
        items: [],
        blockedReason: 'UNPAID_SETTLEMENT',
        message: 'unpaid',
      );
    final settlement = FakeSettlementApi()
      ..items = [settlementItem(bookingNumber: 'TX-DUE')];
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHomeShell(
          bookingRepository: FakeBookingReader(),
          dispatchRepository: dispatch,
          accountApi: FakeAccountApi(),
          settlementApi: settlement,
          onUnauthorized: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settlementBlockedBanner')), findsOneWidget);
    final initialOpenCallsCount = dispatch.openCallsCount;

    dispatch.openCallsResult = const OpenCallList(
      items: [],
      blockedReason: null,
      message: null,
    );

    await tester.tap(find.text('정산'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 콜'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settlementBlockedBanner')), findsNothing);
    expect(dispatch.openCallsCount, greaterThan(initialOpenCallsCount));
  });

  testWidgets('open call shows structured pickup name and address when available', (
    tester,
  ) async {
    await pumpOpenCalls(
      tester,
      onlineReader(
        calls: [
          openCall(
            origin: '999 Nong Prue, Bang Phli',
            destination: '333 Moo 9, Pattaya Beach Road',
            pickupLocation: const BookingLocation(
              name: 'Suvarnabhumi Airport',
              address: '999 Nong Prue, Bang Phli',
            ),
            destinationLocation: const BookingLocation(
              name: 'Hilton Pattaya',
              address: '333 Moo 9, Pattaya Beach Road',
            ),
          ),
        ],
      ),
    );

    expect(
      find.text('Suvarnabhumi Airport'),
      findsOneWidget,
    );
    expect(
      find.text('999 Nong Prue, Bang Phli'),
      findsOneWidget,
    );
    expect(
      find.text('Hilton Pattaya'),
      findsOneWidget,
    );
    expect(
      find.text('333 Moo 9, Pattaya Beach Road'),
      findsOneWidget,
    );
    _expectOpenCallPlaceNameStyle(tester, 'Suvarnabhumi Airport');
    _expectOpenCallPlaceNameStyle(tester, 'Hilton Pattaya');
    _expectOpenCallAddressStyle(tester, '999 Nong Prue, Bang Phli');
    _expectOpenCallAddressStyle(tester, '333 Moo 9, Pattaya Beach Road');
  });

  testWidgets('open call prefers nameTh over name when available', (
    tester,
  ) async {
    await pumpOpenCalls(
      tester,
      onlineReader(
        calls: [
          openCall(
            origin: '999 Nong Prue, Bang Phli',
            destination: '333 Moo 9, Pattaya Beach Road',
            pickupLocation: const BookingLocation(
              name: 'BKK — Suvarnabhumi Airport',
              nameTh: 'ท่าอากาศยานสุวรรณภูมิ',
              address: '999 Nong Prue, Bang Phli',
            ),
            destinationLocation: const BookingLocation(
              name: 'Hilton Pattaya',
              nameTh: 'โรงแรมฮilton พัทยา',
              address: '333 Moo 9, Pattaya Beach Road',
            ),
          ),
        ],
      ),
    );

    expect(
      find.text('ท่าอากาศยานสุวรรณภูมิ'),
      findsOneWidget,
    );
    expect(
      find.text('999 Nong Prue, Bang Phli'),
      findsOneWidget,
    );
    expect(
      find.text('โรงแรมฮilton พัทยา'),
      findsOneWidget,
    );
    expect(
      find.text('333 Moo 9, Pattaya Beach Road'),
      findsOneWidget,
    );
    _expectOpenCallPlaceNameStyle(tester, 'ท่าอากาศยานสุวรรณภูมิ');
    _expectOpenCallAddressStyle(tester, '999 Nong Prue, Bang Phli');
  });

  testWidgets('open call styles airport fallback label as bold primary', (
    tester,
  ) async {
    await pumpOpenCalls(tester, onlineReader());

    _expectOpenCallPlaceNameStyle(tester, 'BKK — Suvarnabhumi Airport');
    _expectOpenCallPlaceNameStyle(tester, 'Pattaya Hotel');
  });

  testWidgets('open call falls back when pickupLocation has address only', (
    tester,
  ) async {
    await pumpOpenCalls(
      tester,
      onlineReader(
        calls: [
          openCall(
            origin: 'BKK',
            pickupLocation: const BookingLocation(
              address: '999 Nong Prue, Bang Phli',
            ),
          ),
        ],
      ),
    );

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    _expectOpenCallPlaceNameStyle(tester, 'BKK — Suvarnabhumi Airport');
  });
}

void _expectOpenCallPlaceNameStyle(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final widget = tester.widget<Text>(finder);
  expect(widget.style?.fontWeight, FontWeight.bold);
  final context = tester.element(finder);
  expect(widget.style?.color, Theme.of(context).colorScheme.primary);
}

void _expectOpenCallAddressStyle(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final widget = tester.widget<Text>(finder);
  expect(widget.style?.fontWeight, isNull);
  expect(widget.style?.color, isNull);
}

class _OpenCallsRefreshHarness extends StatefulWidget {
  const _OpenCallsRefreshHarness({required this.reader});

  final FakeDispatchReader reader;

  @override
  State<_OpenCallsRefreshHarness> createState() =>
      _OpenCallsRefreshHarnessState();
}

class _OpenCallsRefreshHarnessState extends State<_OpenCallsRefreshHarness> {
  int _refreshRequest = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          key: const Key('incrementOpenCallsRefresh'),
          onPressed: () => setState(() => _refreshRequest++),
          child: const Text('refresh'),
        ),
        Expanded(
          child: OpenCallsScreen(
            repository: widget.reader,
            onUnauthorized: () async {},
            onClaimed: () {},
            refreshRequest: _refreshRequest,
          ),
        ),
      ],
    );
  }
}
