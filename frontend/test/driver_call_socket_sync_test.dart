import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_shell_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/services/driver_call_socket_bridge.dart';
import 'package:frontend/features/driver/services/driver_urgent_negotiation_controller.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'driver_access_token': 'driver-test-token',
    });
    DriverUrgentNegotiationController.instance.clear();
    DriverCallSocketBridge.instance.onUrgentEvent = null;
    DriverCallSocketBridge.instance.onCallEvent = null;
  });

  tearDown(() {
    DriverCallSocketBridge.instance.onUrgentEvent = null;
    DriverCallSocketBridge.instance.onCallEvent = null;
    DriverUrgentNegotiationController.instance.clear();
  });

  group('DriverCallSocketBridge.dispatchCall', () {
    test('invokes registered onCallEvent with event and payload', () {
      String? capturedEvent;
      Map<String, dynamic>? capturedPayload;

      DriverCallSocketBridge.instance.onCallEvent = (event, payload) {
        capturedEvent = event;
        capturedPayload = payload;
      };

      const payload = {'bookingNumber': 'TX202607130001'};
      DriverCallSocketBridge.instance.dispatchCall('new', payload);

      expect(capturedEvent, 'new');
      expect(capturedPayload, payload);
    });
  });

  group('DriverShellPage open-call sync', () {
    testWidgets(
      'jobs tab shows new call after socket bridge refresh',
      (tester) async {
        _useTallViewport(tester);
        final api = _OpenCallSyncFakeApi();
        const bookingNumber = 'TX202607130001';

        await tester.pumpWidget(
          MaterialApp(
            home: DriverShellPage(
              api: api,
              settlementApi: _FakeSettlementApi(),
              enableCallSocket: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('배차 가능한 콜이 없습니다'), findsNothing);

        api.releaseOpenCall();
        DriverCallSocketBridge.instance.dispatchCall('new', {
          'bookingNumber': bookingNumber,
        });
        await tester.pump();
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('업무'));
        await tester.pumpAndSettle();

        expect(find.textContaining('배차 가능한 콜이 없습니다'), findsNothing);
        expect(find.textContaining('Pattaya Hotel'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
          findsOneWidget,
        );
      },
    );
  });
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _OpenCallSyncFakeApi extends DriverApiService {
  bool _openCallReleased = false;

  void releaseOpenCall() {
    _openCallReleased = true;
  }

  @override
  Future<String?> getSavedToken() async => 'driver-test-token';

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<DriverJobsToday> getTodayBookings() async =>
      const DriverJobsToday(date: '2026-07-13', items: []);

  @override
  Future<DriverOpenCalls> getOpenCalls() async {
    if (!_openCallReleased) {
      return const DriverOpenCalls(items: []);
    }
    return DriverOpenCalls(items: [_sampleOpenCall()]);
  }

  @override
  Future<DriverStatus> getStatus() async => const DriverStatus(
    driverId: 7,
    active: true,
    online: true,
    status: 'ONLINE',
    hasActiveJob: false,
  );
}

DriverOpenCall _sampleOpenCall() {
  return const DriverOpenCall(
    bookingNumber: 'TX202607130001',
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
  );
}

class _FakeSettlementApi extends DriverSettlementApiService {
  @override
  Future<List<dynamic>> listSettlements() async => [];

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    throw const DriverSettlementApiException('Settlement not found');
  }
}
