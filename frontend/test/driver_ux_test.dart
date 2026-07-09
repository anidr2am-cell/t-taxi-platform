import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_ux.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/pages/driver_jobs_page.dart';
import 'package:frontend/features/driver/pages/driver_login_page.dart';
import 'package:frontend/features/driver/pages/driver_shell_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';

void main() {
  group('DriverUx grouping', () {
    test('active jobs include assigned, arrived, and picked up', () {
      expect(DriverUx.groupForStatus('DRIVER_ASSIGNED'), DriverJobGroup.active);
      expect(DriverUx.groupForStatus('DRIVER_ARRIVED'), DriverJobGroup.active);
      expect(DriverUx.groupForStatus('PICKED_UP'), DriverJobGroup.active);
    });

    test('completed group includes terminal statuses', () {
      expect(DriverUx.groupForStatus('COMPLETED'), DriverJobGroup.completed);
      expect(DriverUx.groupForStatus('CANCELLED'), DriverJobGroup.completed);
      expect(DriverUx.groupForStatus('NO_SHOW'), DriverJobGroup.completed);
    });

    test('groupBookings sorts active before upcoming and completed', () {
      final items = [
        _booking(status: 'COMPLETED', time: '18:00'),
        _booking(
          status: 'DRIVER_ASSIGNED',
          time: '10:00',
          number: 'TX202607010002',
        ),
        _booking(status: 'CONFIRMED', time: '12:00', number: 'TX202607010003'),
        _booking(status: 'PICKED_UP', time: '09:00', number: 'TX202607010004'),
      ];
      final grouped = DriverUx.groupBookings(items);
      expect(grouped[DriverJobGroup.active]!.length, 2);
      expect(grouped[DriverJobGroup.active]!.first.status, 'PICKED_UP');
      expect(grouped[DriverJobGroup.upcoming]!.length, 1);
      expect(grouped[DriverJobGroup.completed]!.length, 1);
    });

    test('canMessageCustomer requires active booking status', () {
      expect(DriverUx.canMessageCustomer('DRIVER_ASSIGNED'), true);
      expect(DriverUx.canMessageCustomer('PICKED_UP'), true);
      expect(DriverUx.canMessageCustomer('COMPLETED'), false);
    });
  });

  testWidgets('login success routes to Jobs shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DriverLoginPage(api: _FakeLoginApi())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'driver@test.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.tap(find.text('로그인 / เข้าสู่ระบบ'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.text('오늘 배정된 예약이 없습니다\n(วันนี้ยังไม่มีงานที่ได้รับมอบหมาย)'),
      findsOneWidget,
    );
  });

  testWidgets('saved token opens Jobs shell on login page load', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverLoginPage(api: _FakeLoginApi(initialToken: 'tok')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('기사 로그인\n(เข้าสู่ระบบคนขับ)'), findsNothing);
  });

  testWidgets('expired token on jobs redirects to login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverShellPage(
          api: _FakeJobsApi(
            initialToken: 'tok',
            error: const DriverApiException('Please log in', statusCode: 401),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('기사 로그인\n(เข้าสู่ระบบคนขับ)'), findsOneWidget);
  });

  testWidgets('jobs list groups active, upcoming, and completed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverJobsPage(
          api: _FakeJobsApi(
            jobs: DriverJobsToday(
              date: '2026-07-01',
              items: [
                _booking(status: 'COMPLETED', time: '18:00'),
                _booking(
                  status: 'DRIVER_ASSIGNED',
                  time: '10:00',
                  number: 'TX202607010002',
                ),
                _booking(
                  status: 'PENDING',
                  time: '12:00',
                  number: 'TX202607010003',
                ),
                _booking(
                  status: 'PICKED_UP',
                  time: '09:00',
                  number: 'TX202607010004',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('진행 중\n(งานปัจจุบัน)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('예정\n(งานที่กำลังจะมาถึง)'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('예정\n(งานที่กำลังจะมาถึง)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('TX202607010001'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('TX202607010001'), findsOneWidget);
  });

  testWidgets('jobs empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverJobsPage(
          api: _FakeJobsApi(
            jobs: const DriverJobsToday(date: '2026-07-01', items: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('오늘 배정된 예약이 없습니다\n(วันนี้ยังไม่มีงานที่ได้รับมอบหมาย)'),
      findsOneWidget,
    );
  });

  testWidgets('jobs error state with retry', (tester) async {
    final api = _FakeJobsApi(error: Exception('network'));
    await tester.pumpWidget(MaterialApp(home: DriverJobsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('network'), findsOneWidget);
    expect(find.text('다시 시도 / ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('jobs list action calls mutation and refreshes', (tester) async {
    final api = _FakeJobsApi(
      jobs: DriverJobsToday(
        date: '2026-07-01',
        items: [
          _booking(status: 'DRIVER_ASSIGNED', actions: ['START_ON_ROUTE']),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DriverJobsPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '운행 시작 / เริ่มเดินทาง'));
    await tester.pumpAndSettle();

    expect(api.startRouteCalls, 1);
    expect(api.todayCalls, 2);
    expect(
      find.widgetWithText(FilledButton, '기사 도착 / ถึงจุดรับแล้ว'),
      findsOneWidget,
    );
  });

  testWidgets('message button opens booking chat room', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['VIEW_DETAILS'],
              phone: '+66123456789',
            ),
          ),
          chatPageBuilder: (bookingNumber) =>
              Scaffold(body: Text('chat:$bookingNumber')),
        ),
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

  testWidgets('message button does not require customer phone', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['VIEW_DETAILS'],
              phone: '',
            ),
          ),
          chatPageBuilder: (bookingNumber) =>
              Scaffold(body: Text('chat:$bookingNumber')),
        ),
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

  testWidgets('cancelled booking is read-only without primary action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(status: 'CANCELLED', actions: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 시작 / เริ่มเดินทาง'), findsNothing);
    expect(find.text('Cancelled'), findsWidgets);
  });

  testWidgets('stale status error refreshes booking', (tester) async {
    final api = _FakeDetailApi(
      detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
      arrivedError: const DriverApiException(
        'Invalid status transition',
        errorCode: 'INVALID_STATUS_TRANSITION',
      ),
      refreshed: _booking(status: 'DRIVER_ARRIVED', actions: ['COMPLETE_TRIP']),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, '기사 도착 / ถึงจุดรับแล้ว'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invalid status transition'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '운행 완료 / จบงาน'), findsOneWidget);
  });

  testWidgets('jobs layout has no horizontal overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: DriverJobsPage(
          api: _FakeJobsApi(
            jobs: DriverJobsToday(
              date: '2026-07-01',
              items: [
                _booking(
                  status: 'DRIVER_ASSIGNED',
                  origin:
                      'Suvarnabhumi Airport Terminal 1 International Arrivals Hall',
                  destination:
                      'Pattaya Beach Road Hotel Resort and Spa Thailand',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

DriverBooking _booking({
  String status = 'DRIVER_ASSIGNED',
  String time = '09:30',
  String number = 'TX202607010001',
  List<String> actions = const ['VIEW_DETAILS'],
  String? phone = '+66123456789',
  String origin = 'BKK Airport',
  String destination = 'Pattaya Hotel',
}) {
  return DriverBooking(
    bookingNumber: number,
    status: status,
    serviceTypeName: 'Airport Pickup',
    pickupDate: '2026-07-01',
    pickupTime: time,
    origin: origin,
    destination: destination,
    passengerCount: 2,
    vehicleTypeName: 'SUV',
    customerDisplayName: 'Kim',
    customerPhone: phone,
    allowedActions: actions,
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeLoginApi extends DriverApiService {
  _FakeLoginApi({String? initialToken}) : _token = initialToken;

  String? _token;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<void> login({required String email, required String password}) async {
    _token = 'test-token';
  }

  @override
  Future<DriverJobsToday> getTodayBookings() async =>
      const DriverJobsToday(date: '2026-07-01', items: []);

  @override
  Future<DriverStatus> getStatus() async => const DriverStatus(
    driverId: 7,
    active: true,
    online: false,
    status: 'OFFLINE',
    hasActiveJob: false,
  );
}

class _FakeJobsApi extends DriverApiService {
  _FakeJobsApi({this.jobs, this.error, String? initialToken})
    : _token = initialToken;

  DriverJobsToday? jobs;
  final Object? error;
  final String? _token;
  int todayCalls = 0;
  int startRouteCalls = 0;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<DriverJobsToday> getTodayBookings() async {
    todayCalls += 1;
    if (error != null) throw error!;
    return jobs ?? const DriverJobsToday(date: '2026-07-01', items: []);
  }

  @override
  Future<DriverBooking> startOnRoute(String bookingNumber) async {
    startRouteCalls += 1;
    final current =
        jobs ?? const DriverJobsToday(date: '2026-07-01', items: []);
    final updatedItems = current.items.map((booking) {
      if (booking.bookingNumber != bookingNumber) return booking;
      return _booking(
        status: 'ON_ROUTE',
        number: booking.bookingNumber,
        actions: ['MARK_ARRIVED'],
        time: booking.pickupTime,
        origin: booking.origin,
        destination: booking.destination,
      );
    }).toList();
    jobs = DriverJobsToday(date: current.date, items: updatedItems);
    return updatedItems.firstWhere(
      (booking) => booking.bookingNumber == bookingNumber,
    );
  }

  @override
  Future<DriverStatus> getStatus() async => const DriverStatus(
    driverId: 7,
    active: true,
    online: false,
    status: 'OFFLINE',
    hasActiveJob: false,
  );
}

class _FakeDetailApi extends DriverApiService {
  _FakeDetailApi({
    required DriverBooking detail,
    this.arrivedError,
    this.refreshed,
  }) : _current = detail;

  DriverBooking _current;
  final DriverApiException? arrivedError;
  final DriverBooking? refreshed;
  bool _refreshAfterError = false;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    if (_refreshAfterError && refreshed != null) {
      _current = refreshed!;
      _refreshAfterError = false;
    }
    return _current;
  }

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    if (arrivedError != null) {
      _refreshAfterError = true;
      throw arrivedError!;
    }
    return _current;
  }
}
