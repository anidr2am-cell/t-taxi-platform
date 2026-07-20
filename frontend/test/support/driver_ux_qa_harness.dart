import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_shell_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

/// Shared helpers for PR #72 automated QA (mock/fixture only).
class DriverUxQaHarness {
  DriverUxQaHarness._();

  static const viewports = <Size>[
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(768, 1024),
  ];

  static const textScales = <double>[1.0, 1.3];

  static Future<void> configureViewport(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      () => tester.platformDispatcher.clearTextScaleFactorTestValue(),
    );
  }

  static void expectNoOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull);
  }

  static void expectMinTouchHeight(
    WidgetTester tester,
    Finder finder, {
    double minHeight = 44,
  }) {
    final elements = finder.evaluate();
    expect(elements, isNotEmpty);
    for (final element in elements) {
      final box = tester.renderObject<RenderBox>(find.byWidget(element.widget));
      expect(box.size.height, greaterThanOrEqualTo(minHeight));
    }
  }

  static void expectPrimaryCtaHeight(WidgetTester tester, Finder finder) {
    expectMinTouchHeight(tester, finder, minHeight: 52);
  }

  static Widget shell({
    required QaDriverApi api,
    QaSettlementApi? settlementApi,
  }) {
    return MaterialApp(
      home: DriverShellPage(
        api: api,
        settlementApi: settlementApi ?? QaSettlementApi(),
      ),
    );
  }

  static Widget page(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }
}

DriverBooking qaBooking({
  String status = 'DRIVER_ASSIGNED',
  String time = '09:30',
  String number = 'TX202607010001',
  List<String> actions = const ['VIEW_DETAILS'],
  String? phone = '+66123456789',
  String origin = 'BKK Airport',
  String destination = 'Pattaya Hotel',
  bool nameSignRequested = false,
  DriverBookingLocation? pickupLocation,
  DriverBookingLocation? destinationLocation,
  Map<String, dynamic>? luggage,
  String? flightNumber,
  double? customerPaymentAmount,
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
    nameSignRequested: nameSignRequested,
    pickupLocation: pickupLocation,
    destinationLocation: destinationLocation,
    luggage: luggage,
    flightNumber: flightNumber,
    customerPaymentAmount: customerPaymentAmount ?? 2500,
    customerPaymentCurrency: 'THB',
  );
}

DriverOpenCall qaOpenCall({String number = 'TX202607130001'}) {
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
    companyCommissionAmount: 300,
    companyCommissionCurrency: 'THB',
    driverExpectedIncomeAmount: 2200,
    driverExpectedIncomeCurrency: 'THB',
    passengerCount: 2,
    luggage: const {
      'carriers20Inch': 1,
      'carriers24InchPlus': 2,
      'golfBags': 1,
    },
  );
}

class QaDriverApi extends DriverApiService {
  QaDriverApi({
    this.jobs,
    this.openCalls = const [],
    this.openCallBlockedReason,
    this.openCallBlockedMessage,
    this.loadError,
    this.claimError,
    this.claimDelay = Duration.zero,
    this.online = true,
    this.hasActiveJob = false,
    String? initialToken,
    this.unreadNotifications = 0,
  }) : _token = initialToken ?? 'qa-token';

  DriverJobsToday? jobs;
  List<DriverOpenCall> openCalls;
  String? openCallBlockedReason;
  String? openCallBlockedMessage;
  Object? loadError;
  Object? claimError;
  Duration claimDelay;
  bool online;
  bool hasActiveJob;
  int unreadNotifications;
  final String? _token;

  int todayCalls = 0;
  int claimCalls = 0;
  bool claimInFlight = false;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<int> getUnreadNotificationCount() async => unreadNotifications;

  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async => {
    'items': [],
  };

  @override
  Future<DriverJobsToday> getTodayBookings() async {
    todayCalls += 1;
    if (loadError != null) throw loadError!;
    return jobs ?? const DriverJobsToday(date: '2026-07-01', items: []);
  }

  @override
  Future<DriverOpenCalls> getOpenCalls() async {
    if (loadError != null) throw loadError!;
    return DriverOpenCalls(
      items: openCalls,
      blockedReason: openCallBlockedReason,
      message: openCallBlockedMessage,
    );
  }

  @override
  Future<DriverBooking> claimOpenCall(String bookingNumber) async {
    claimCalls += 1;
    claimInFlight = true;
    await Future<void>.delayed(claimDelay);
    claimInFlight = false;
    if (claimError != null) throw claimError!;
    return qaBooking(status: 'DRIVER_ASSIGNED', number: bookingNumber);
  }

  @override
  Future<DriverStatus> getStatus() async => DriverStatus(
    driverId: 7,
    active: true,
    online: online,
    status: online ? 'ONLINE' : 'OFFLINE',
    hasActiveJob: hasActiveJob,
  );

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    return qaBooking(number: bookingNumber);
  }
}

class QaSettlementApi extends DriverSettlementApiService {
  QaSettlementApi({this.settlements = const {}});

  final Map<String, Map<String, dynamic>> settlements;

  @override
  Future<List<dynamic>> listSettlements() async => settlements.values.toList();

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    final item = settlements[bookingNumber];
    if (item == null) {
      throw const DriverSettlementApiException('Settlement not found');
    }
    return item;
  }
}
