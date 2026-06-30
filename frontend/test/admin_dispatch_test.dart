import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_booking_detail_page.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/widgets/recommend_drivers_dialog.dart';

class _FakeAdminApi extends AdminDispatchApiService {
  _FakeAdminApi({
    this.token,
    this.bookingsResponse,
    this.bookingsError,
    this.detailResponse,
    this.driversResponse,
    this.assignCalls = 0,
    this.reassignCalls = 0,
    this.autoAssignCalls = 0,
    this.lastAssignmentState,
    this.lastStatus,
    this.candidatesResponse,
    this.candidatesError,
    this.autoAssignError,
    this.reissueResponse,
  });

  final String? token;
  final Map<String, dynamic>? bookingsResponse;
  final Object? bookingsError;
  final Map<String, dynamic>? detailResponse;
  final List<dynamic>? driversResponse;
  int assignCalls;
  int reassignCalls;
  int autoAssignCalls;
  String? lastAssignmentState;
  String? lastStatus;
  final Map<String, dynamic>? candidatesResponse;
  final Object? candidatesError;
  final Object? autoAssignError;
  final Map<String, dynamic>? reissueResponse;

  @override
  Future<String?> getSavedToken() async => token;

  @override
  Future<Map<String, dynamic>> listBookings({
    String? search,
    String? status,
    String? assignmentState,
    String? serviceDateFrom,
    String? serviceDateTo,
    int page = 1,
    int limit = 20,
  }) async {
    lastAssignmentState = assignmentState;
    lastStatus = status;
    if (bookingsError != null) throw bookingsError!;
    return bookingsResponse ?? {'page': 1, 'total': 0, 'items': []};
  }

  @override
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    return detailResponse ??
        {
          'bookingNumber': bookingNumber,
          'status': 'PENDING',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
          'allowedActions': ['ASSIGN_DRIVER'],
        };
  }

  @override
  Future<List<dynamic>> listDrivers() async {
    return driversResponse ??
        [
          {
            'driverId': 6,
            'displayName': 'Driver A',
            'phone': '+6600',
            'eligibilityState': 'ACTIVE',
            'assignmentEligible': true,
            'activeAssignmentCount': 0,
          },
        ];
  }

  @override
  Future<Map<String, dynamic>> assignDriver(String bookingNumber, int driverId) async {
    assignCalls += 1;
    return {'assignmentId': 1, 'driver': {'driverId': driverId}};
  }

  @override
  Future<Map<String, dynamic>> reassignDriver(
    String bookingNumber,
    int driverId,
    String reason,
  ) async {
    reassignCalls += 1;
    return {'assignmentId': 2, 'driver': {'driverId': driverId}};
  }

  @override
  Future<Map<String, dynamic>> getDriverCandidates(String bookingNumber) async {
    if (candidatesError != null) throw candidatesError!;
    return candidatesResponse ??
        {
          'bookingId': 1,
          'bookingNumber': bookingNumber,
          'recommendedDriverId': 6,
          'assignmentVersion': 0,
          'candidates': [
            {
              'driverId': 6,
              'displayName': 'Driver A',
              'vehicleTypeCode': 'SUV',
              'online': true,
              'activeJobCount': 0,
              'distanceKm': 3.2,
              'locationFresh': true,
              'score': 92,
              'reasons': ['VEHICLE_MATCH', 'ONLINE'],
              'eligible': true,
            },
          ],
          'excluded': [
            {'driverId': 9, 'displayName': 'Driver B', 'reasons': ['OFFLINE']},
          ],
        };
  }

  @override
  Future<Map<String, dynamic>> autoAssignDriver(
    String bookingNumber, {
    int? driverId,
    bool useTopCandidate = false,
    int? expectedAssignmentVersion,
  }) async {
    if (autoAssignError != null) throw autoAssignError!;
    autoAssignCalls += 1;
    return {
      'assignmentId': 3,
      'driver': {'driverId': driverId ?? 6},
      'bookingStatus': 'DRIVER_ASSIGNED',
    };
  }

  @override
  Future<Map<String, dynamic>> reissueQr(String bookingNumber, String type) async {
    return reissueResponse ??
        {
          'bookingNumber': bookingNumber,
          'qrType': type,
          if (type == 'BOARDING') 'boardingQrToken': 'dev-boarding-token',
          if (type == 'DROPOFF') 'dropoffQrToken': 'dev-dropoff-token',
          'expiresAt': '2099-01-01 00:00:00',
        };
  }
}

Map<String, dynamic> _queueItem(String bookingNumber) => {
      'bookingNumber': bookingNumber,
      'status': 'PENDING',
      'scheduledPickupAt': '2026-07-01 09:30:00',
      'origin': 'BKK',
      'destination': 'Pattaya',
      'customerDisplayName': 'Kim',
      'activeAssignment': null,
    };

void main() {
  testWidgets('shows login when token missing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(api: _FakeAdminApi(token: null)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin sign in'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(
          api: _FakeAdminApi(token: 'token', bookingsResponse: {'page': 1, 'total': 0, 'items': []}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No bookings found'), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(
          api: _FakeAdminApi(
            token: 'token',
            bookingsError: const AdminDispatchApiException('Network error'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Network error'), findsOneWidget);
  });

  testWidgets('assignment filter requests UNASSIGNED bookings', (tester) async {
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {'page': 1, 'total': 0, 'items': []},
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned').last);
    await tester.pumpAndSettle();
    expect(api.lastAssignmentState, 'UNASSIGNED');
  });

  testWidgets('opens booking detail from queue', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(
          api: _FakeAdminApi(
            token: 'token',
            bookingsResponse: {
              'page': 1,
              'total': 1,
              'items': [_queueItem('TX202607010001')],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TX202607010001'));
    await tester.pumpAndSettle();
    expect(find.text('Assign driver'), findsOneWidget);
  });

  testWidgets('terminal booking hides assign action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'COMPLETED',
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
              'allowedActions': [],
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assign driver'), findsNothing);
    expect(find.text('Reassign driver'), findsNothing);
  });

  testWidgets('assign-driver flow confirms and calls API once', (tester) async {
    final api = _FakeAdminApi(token: 'token');
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Booking'));
    await tester.pumpAndSettle();
    expect(api.assignCalls, 1);
  });

  testWidgets('reassign flow requires reason and calls API once', (tester) async {
    final api = _FakeAdminApi(
      detailResponse: {
        'bookingNumber': 'TX202607010001',
        'status': 'DRIVER_ASSIGNED',
        'route': {
          'origin': {'address': 'BKK'},
          'destination': {'address': 'Pattaya'},
        },
        'customer': {'name': 'Kim', 'phone': '+66123456789'},
        'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
        'allowedActions': ['REASSIGN_DRIVER'],
        'activeAssignment': {'driverDisplayName': 'Old Driver'},
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reassign driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Closer to pickup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Booking'));
    await tester.pumpAndSettle();
    expect(api.reassignCalls, 1);
  });

  testWidgets('shows recommend drivers action when allowed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'CONFIRMED',
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
              'allowedActions': ['ASSIGN_DRIVER', 'RECOMMEND_DRIVERS'],
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recommend drivers'), findsOneWidget);
    expect(find.text('Assign driver'), findsOneWidget);
  });

  testWidgets('recommend drivers dialog shows candidates and excluded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRecommendDriversDialog(
              context: context,
              api: _FakeAdminApi(),
              bookingNumber: 'TX202607010001',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Recommend drivers'), findsOneWidget);
    expect(find.text('Driver A (SUV)'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Excluded'), findsOneWidget);
    expect(find.text('Driver B'), findsOneWidget);
  });

  testWidgets('assign recommended driver calls auto assign once', (tester) async {
    final api = _FakeAdminApi(
      detailResponse: {
        'bookingNumber': 'TX202607010001',
        'status': 'CONFIRMED',
        'route': {
          'origin': {'address': 'BKK'},
          'destination': {'address': 'Pattaya'},
        },
        'customer': {'name': 'Kim', 'phone': '+66123456789'},
        'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
        'allowedActions': ['RECOMMEND_DRIVERS'],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommend drivers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign recommended'));
    await tester.pumpAndSettle();
    expect(api.autoAssignCalls, 1);
    expect(find.text('Driver assigned successfully'), findsOneWidget);
  });

  testWidgets('recommend drivers shows error and retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRecommendDriversDialog(
              context: context,
              api: _FakeAdminApi(
                candidatesError: const AdminDispatchApiException('Server error'),
              ),
              bookingNumber: 'TX202607010001',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Server error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows dev QR reissue actions when enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'DRIVER_ARRIVED',
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
              'allowedActions': [],
              'devQrTools': {
                'qrReissueEnabled': true,
                'disabledReason': null,
                'boarding': {
                  'reissueAvailable': true,
                  'consumed': false,
                  'previouslyIssued': true,
                  'unavailableReason': null,
                },
                'dropoff': {
                  'reissueAvailable': false,
                  'consumed': false,
                  'previouslyIssued': false,
                  'unavailableReason': 'Dropoff QR reissue requires status PICKED_UP',
                },
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QR management'), findsOneWidget);
    expect(find.text('Reissue boarding QR'), findsOneWidget);
  });

  testWidgets('shows QR management section when reissue disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'DRIVER_ARRIVED',
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
              'allowedActions': [],
              'devQrTools': {
                'qrReissueEnabled': false,
                'disabledReason': 'Set ALLOW_DEV_QR_REISSUE=true on the backend and restart',
                'boarding': {
                  'reissueAvailable': false,
                  'consumed': false,
                  'previouslyIssued': true,
                  'unavailableReason': null,
                },
                'dropoff': {
                  'reissueAvailable': false,
                  'consumed': false,
                  'previouslyIssued': false,
                  'unavailableReason': null,
                },
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QR management'), findsOneWidget);
    expect(find.text('Reissue boarding QR'), findsNothing);
    expect(
      find.text('Set ALLOW_DEV_QR_REISSUE=true on the backend and restart'),
      findsOneWidget,
    );
  });

  testWidgets('dev QR reissue shows token once dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'DRIVER_ARRIVED',
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {'totalAmount': 1200, 'currency': 'THB', 'paymentMethod': 'PAY_DRIVER'},
              'allowedActions': [],
              'devQrTools': {
                'qrReissueEnabled': true,
                'disabledReason': null,
                'boarding': {
                  'reissueAvailable': true,
                  'consumed': false,
                  'previouslyIssued': true,
                  'unavailableReason': null,
                },
                'dropoff': {
                  'reissueAvailable': false,
                  'consumed': false,
                  'previouslyIssued': false,
                  'unavailableReason': null,
                },
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reissue boarding QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reissue'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminQrReissueToken')), findsOneWidget);
    expect(find.text('dev-boarding-token'), findsOneWidget);
  });
}
