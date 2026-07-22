import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_jobs_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/services/driver_call_socket_bridge.dart';
import 'package:frontend/features/driver/services/driver_urgent_negotiation_controller.dart';

void main() {
  setUp(() {
    DriverUrgentNegotiationController.instance.clear();
  });

  tearDown(() {
    DriverUrgentNegotiationController.instance.clear();
  });

  testWidgets('urgent lock success opens ETA dialog automatically', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = FakeUrgentJobsApi(
      initialToken: 'tok',
      online: true,
      openCalls: [urgentOpenCall()],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DriverJobsPage(api: api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '수락 / รับงาน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.lockCalls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('urgent lock 409 removes card and shows message', (tester) async {
    _useTallViewport(tester);
    final api = FakeUrgentJobsApi(
      initialToken: 'tok',
      online: true,
      lockError: const DriverApiException(
        'Already locked',
        statusCode: 409,
        errorCode: 'URGENT_ALREADY_LOCKED',
      ),
      openCalls: [urgentOpenCall(number: 'TX202607130100')],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DriverJobsPage(api: api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '수락 / รับงาน'));
    await tester.pumpAndSettle();

    expect(api.lockCalls, 1);
    expect(find.textContaining('다른 기사가 이미 수락한 콜입니다'), findsOneWidget);
    expect(find.text('TX202607130100'), findsNothing);
  });

  testWidgets('urgent ETA 422 shows inline error inside dialog', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = FakeUrgentJobsApi(
      initialToken: 'tok',
      online: true,
      etaError: const DriverApiException(
        'ETA not fast enough',
        statusCode: 422,
        errorCode: 'URGENT_ETA_NOT_FAST_ENOUGH',
      ),
      openCalls: [urgentOpenCall(number: 'TX202607130101')],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DriverJobsPage(api: api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '수락 / รับงาน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextFormField), '30');
    await tester.tap(find.widgetWithText(TextButton, '제출 / ส่ง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('이전 거절보다 더 빠른 도착 예상 시간'),
      findsOneWidget,
    );
  });

  testWidgets('urgent ETA lock timer expiry closes dialog and shows notice', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = FakeUrgentJobsApi.expiredLock(
      initialToken: 'tok',
      online: true,
      openCalls: [urgentOpenCall(number: 'TX202607130102')],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DriverJobsPage(api: api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '수락 / รับงาน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('도착 예상 시간 입력 시간이 만료되었습니다'),
      findsOneWidget,
    );
  });

  testWidgets('urgent confirmed socket shows confirmation banner', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = FakeUrgentJobsApi(
      initialToken: 'tok',
      online: true,
      openCalls: const [],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DriverJobsPage(api: api))),
    );
    await tester.pumpAndSettle();

    DriverCallSocketBridge.instance.dispatch('confirmed', {
      'bookingNumber': 'TX202607130103',
      'negotiationId': 100,
    });
    await tester.pump();

    expect(
      find.textContaining('고객이 수락했습니다. 예약이 배정되었습니다'),
      findsOneWidget,
    );
  });
}

DriverOpenCall urgentOpenCall({String number = 'TX202607130099'}) {
  return DriverOpenCall(
    bookingNumber: number,
    status: 'OPEN',
    pickupDate: '2026-07-13',
    pickupTime: '10:30',
    origin: 'BKK Airport',
    destination: 'Pattaya Hotel',
    serviceTypeName: 'Airport pickup',
    vehicleTypeName: 'Van',
    amount: 2500,
    currency: 'THB',
    customerPaymentAmount: 2500,
    customerPaymentCurrency: 'THB',
    passengerCount: 2,
    isUrgentRequest: true,
    negotiationId: 100,
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class FakeUrgentJobsApi extends DriverApiService {
  FakeUrgentJobsApi({
    this.openCalls = const [],
    this.lockError,
    this.etaError,
    this.online = false,
    String? initialToken,
    this.lockExpiresAt = '2099-07-23 01:30:00.000',
  }) : _token = initialToken;

  FakeUrgentJobsApi.expiredLock({
    required String? initialToken,
    required bool online,
    required List<DriverOpenCall> openCalls,
  }) : this(
         initialToken: initialToken,
         online: online,
         openCalls: openCalls,
         lockExpiresAt: '2000-01-01 00:00:00.000',
       );

  final List<DriverOpenCall> openCalls;
  final Object? lockError;
  final Object? etaError;
  final bool online;
  final String lockExpiresAt;
  final String? _token;
  int lockCalls = 0;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<DriverJobsToday> getTodayBookings() async =>
      const DriverJobsToday(date: '2026-07-01', items: []);

  @override
  Future<DriverOpenCalls> getOpenCalls() async =>
      DriverOpenCalls(items: openCalls);

  @override
  Future<DriverStatus> getStatus() async => DriverStatus(
    driverId: 7,
    active: true,
    online: online,
    status: online ? 'ONLINE' : 'OFFLINE',
    hasActiveJob: false,
  );

  @override
  Future<Map<String, dynamic>> lockUrgentCall(String bookingNumber) async {
    lockCalls += 1;
    if (lockError != null) throw lockError!;
    return {
      'bookingNumber': bookingNumber,
      'negotiationId': 100,
      'attemptNumber': 1,
      'status': 'LOCKED',
      'lockExpiresAt': lockExpiresAt,
    };
  }

  @override
  Future<Map<String, dynamic>> submitUrgentCallEta(
    String bookingNumber,
    int etaMinutes,
  ) async {
    if (etaError != null) throw etaError!;
    return {
      'bookingNumber': bookingNumber,
      'etaMinutes': etaMinutes,
      'status': 'AWAITING_CUSTOMER',
      'customerDecisionExpiresAt': '2099-07-23 01:32:00.000',
    };
  }
}
