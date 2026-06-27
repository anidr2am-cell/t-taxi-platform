import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_ux.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
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
        _booking(status: 'DRIVER_ASSIGNED', time: '10:00', number: 'TX202607010002'),
        _booking(status: 'CONFIRMED', time: '12:00', number: 'TX202607010003'),
        _booking(status: 'PICKED_UP', time: '09:00', number: 'TX202607010004'),
      ];
      final grouped = DriverUx.groupBookings(items);
      expect(grouped[DriverJobGroup.active]!.length, 2);
      expect(grouped[DriverJobGroup.active]!.first.status, 'PICKED_UP');
      expect(grouped[DriverJobGroup.upcoming]!.length, 1);
      expect(grouped[DriverJobGroup.completed]!.length, 1);
    });

    test('canCallCustomer requires phone and active status', () {
      expect(DriverUx.canCallCustomer('DRIVER_ASSIGNED', '+66123'), true);
      expect(DriverUx.canCallCustomer('COMPLETED', '+66123'), false);
      expect(DriverUx.canCallCustomer('DRIVER_ASSIGNED', null), false);
    });
  });

  testWidgets('login success routes to Jobs shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverLoginPage(api: _FakeLoginApi()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'driver@test.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('No jobs today'), findsOneWidget);
  });

  testWidgets('saved token opens Jobs shell on login page load', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverLoginPage(api: _FakeLoginApi(initialToken: 'tok')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Driver Login'), findsNothing);
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

    expect(find.text('Driver Login'), findsOneWidget);
  });

  testWidgets('jobs list groups active, upcoming, and completed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverJobsPage(
          api: _FakeJobsApi(
            jobs: DriverJobsToday(
              date: '2026-07-01',
              items: [
                _booking(status: 'COMPLETED', time: '18:00'),
                _booking(status: 'DRIVER_ASSIGNED', time: '10:00', number: 'TX202607010002'),
                _booking(status: 'PENDING', time: '12:00', number: 'TX202607010003'),
                _booking(status: 'PICKED_UP', time: '09:00', number: 'TX202607010004'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active / Current'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
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

    expect(find.text('No jobs today'), findsOneWidget);
  });

  testWidgets('jobs error state with retry', (tester) async {
    final api = _FakeJobsApi(error: Exception('network'));
    await tester.pumpWidget(
      MaterialApp(home: DriverJobsPage(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load jobs'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('call button when phone exists', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['MARK_ARRIVED'],
              phone: '+66123456789',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Call customer'), findsOneWidget);
  });

  testWidgets('call button hidden without phone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['MARK_ARRIVED'],
              phone: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Call customer'), findsNothing);
  });

  testWidgets('cancelled booking is read-only without primary action', (tester) async {
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

    expect(find.text('Mark arrived'), findsNothing);
    expect(find.text('Cancelled'), findsWidgets);
  });

  testWidgets('stale status error refreshes booking', (tester) async {
    final api = _FakeDetailApi(
      detail: _booking(status: 'DRIVER_ASSIGNED', actions: ['MARK_ARRIVED']),
      arrivedError: const DriverApiException(
        'Invalid status transition',
        errorCode: 'INVALID_STATUS_TRANSITION',
      ),
      refreshed: _booking(status: 'DRIVER_ARRIVED', actions: ['SCAN_BOARDING_QR']),
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

    await tester.tap(find.widgetWithText(FilledButton, 'Mark arrived'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid status transition'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Scan boarding QR'),
      findsOneWidget,
    );
  });

  testWidgets('jobs layout has no horizontal overflow at 360px', (tester) async {
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
                  origin: 'Suvarnabhumi Airport Terminal 1 International Arrivals Hall',
                  destination: 'Pattaya Beach Road Hotel Resort and Spa Thailand',
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
}

class _FakeJobsApi extends DriverApiService {
  _FakeJobsApi({this.jobs, this.error, String? initialToken}) : _token = initialToken;

  final DriverJobsToday? jobs;
  final Object? error;
  final String? _token;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<DriverJobsToday> getTodayBookings() async {
    if (error != null) throw error!;
    return jobs ?? const DriverJobsToday(date: '2026-07-01', items: []);
  }
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
