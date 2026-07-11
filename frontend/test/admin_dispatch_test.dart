import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_booking_detail_page.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/widgets/recommend_drivers_dialog.dart';
import 'package:frontend/features/admin_settlement/services/admin_settlement_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _FakeAdminApi extends AdminDispatchApiService {
  _FakeAdminApi({
    this.token,
    this.bookingsResponse,
    this.bookingsError,
    this.detailResponse,
    this.detailResponses,
    this.candidatesError,
  });

  final String? token;
  final Map<String, dynamic>? bookingsResponse;
  final Object? bookingsError;
  final Map<String, dynamic>? detailResponse;
  final List<Map<String, dynamic>>? detailResponses;
  int detailCalls = 0;
  int assignCalls = 0;
  int reassignCalls = 0;
  int autoAssignCalls = 0;
  String? lastAssignmentState;
  String? lastStatus;
  String? lastView;
  final Object? candidatesError;

  @override
  Future<String?> getSavedToken() async => token;

  @override
  Future<Map<String, dynamic>> listBookings({
    String? view,
    String? search,
    String? status,
    String? assignmentState,
    String? serviceDateFrom,
    String? serviceDateTo,
    String? serviceType,
    String? origin,
    String? destination,
    String? settlementStatus,
    bool? lowRating,
    bool? unassigned,
    bool? hasInquiry,
    int page = 1,
    int limit = 20,
  }) async {
    lastAssignmentState = assignmentState;
    lastStatus = status;
    lastView = view;
    if (bookingsError != null) throw bookingsError!;
    return bookingsResponse ?? {'page': 1, 'total': 0, 'items': []};
  }

  @override
  Future<Map<String, dynamic>> getBookingsSummary() async {
    return {
      'needsAction': 2,
      'unassigned': 1,
      'today': 3,
      'inProgress': 1,
      'settlementPending': 1,
      'issues': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    final sequence = detailResponses;
    if (sequence != null && sequence.isNotEmpty) {
      final index = detailCalls < sequence.length
          ? detailCalls
          : sequence.length - 1;
      detailCalls += 1;
      return sequence[index];
    }
    return detailResponse ??
        {
          'bookingNumber': bookingNumber,
          'status': 'PENDING',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'activeAssignment': null,
          'allowedActions': ['ASSIGN_DRIVER'],
        };
  }

  @override
  Future<List<dynamic>> listDrivers() async {
    return [
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
  Future<Map<String, dynamic>> assignDriver(
    String bookingNumber,
    int driverId,
  ) async {
    assignCalls += 1;
    return {
      'assignmentId': 1,
      'driver': {'driverId': driverId},
    };
  }

  @override
  Future<Map<String, dynamic>> reassignDriver(
    String bookingNumber,
    int driverId,
    String reason,
  ) async {
    reassignCalls += 1;
    return {
      'assignmentId': 2,
      'driver': {'driverId': driverId},
    };
  }

  @override
  Future<Map<String, dynamic>> getDriverCandidates(String bookingNumber) async {
    if (candidatesError != null) throw candidatesError!;
    return {
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
        {
          'driverId': 9,
          'displayName': 'Driver B',
          'reasons': ['OFFLINE'],
        },
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
    autoAssignCalls += 1;
    return {
      'assignmentId': 3,
      'driver': {'driverId': driverId ?? 6},
      'bookingStatus': 'DRIVER_ASSIGNED',
    };
  }

  @override
  Future<Map<String, dynamic>> reissueQr(
    String bookingNumber,
    String type,
  ) async {
    return {
      'bookingNumber': bookingNumber,
      'qrType': type,
      if (type == 'BOARDING') 'boardingQrToken': 'dev-boarding-token',
      if (type == 'DROPOFF') 'dropoffQrToken': 'dev-dropoff-token',
      'expiresAt': '2099-01-01 00:00:00',
    };
  }
}

class _FakeSettlementApi extends AdminSettlementApiService {
  _FakeSettlementApi({required this.detail, this.approveError});

  final Map<String, dynamic> detail;
  final Object? approveError;
  int approveCalls = 0;
  int receiptCalls = 0;

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async =>
      detail;

  @override
  Future<Map<String, dynamic>> approve(String bookingNumber) async {
    approveCalls += 1;
    if (approveError != null) throw approveError!;
    return {...detail, 'commissionStatus': 'APPROVED'};
  }

  @override
  Future<AdminSettlementReceipt> getReceipt(String bookingNumber) async {
    receiptCalls += 1;
    return AdminSettlementReceipt(
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      contentType: 'application/pdf',
      filename: 'transfer-slip.pdf',
    );
  }
}

Map<String, dynamic> _settlementPendingDetail() => {
  'bookingNumber': 'TX202607010001',
  'status': 'SETTLEMENT_PENDING',
  'route': {
    'origin': {'address': 'BKK'},
    'destination': {'address': 'Pattaya'},
  },
  'customer': {'name': 'Kim', 'phone': '+66123456789'},
  'pricing': {
    'totalAmount': 1200,
    'currency': 'THB',
    'paymentMethod': 'PAY_DRIVER',
  },
  'activeAssignment': {'driverDisplayName': 'Driver A'},
  'allowedActions': [],
};

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
          api: _FakeAdminApi(
            token: 'token',
            bookingsResponse: {'page': 1, 'total': 0, 'items': []},
          ),
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

  testWidgets('summary unassigned card requests UNASSIGNED bookings', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {'page': 1, 'total': 0, 'items': []},
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned').first);
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

  testWidgets('issues summary card switches to issues view', (tester) async {
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {'page': 1, 'total': 0, 'items': []},
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issues').first);
    await tester.pumpAndSettle();
    expect(api.lastView, 'issues');
  });

  testWidgets('shows needs action tab and summary cards by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(
          api: _FakeAdminApi(
            token: 'token',
            bookingsResponse: {
              'page': 1,
              'total': 2,
              'items': [
                _queueItem('TX-NEW'),
                {
                  ..._queueItem('TX-EXISTING'),
                  'activeAssignment': {
                    'driverDisplayName': 'Driver A',
                    'status': 'ASSIGNED',
                  },
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Needs action'), findsWidgets);
    expect(find.text('TX-NEW'), findsOneWidget);
    expect(find.text('TX-EXISTING'), findsOneWidget);
  });

  testWidgets('assigned driver is rendered in booking list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(
          api: _FakeAdminApi(
            token: 'token',
            bookingsResponse: {
              'page': 1,
              'total': 1,
              'items': [
                {
                  ..._queueItem('TX202607010001'),
                  'activeAssignment': {
                    'driverDisplayName': 'Driver A',
                    'status': 'ASSIGNED',
                  },
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assigned driver: Driver A'), findsOneWidget);
  });

  testWidgets('unassigned label is rendered in booking list and detail', (
    tester,
  ) async {
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
    expect(find.text('Assigned driver: Unassigned'), findsOneWidget);

    await tester.tap(find.text('TX202607010001'));
    await tester.pumpAndSettle();
    expect(find.text('Assigned driver'), findsOneWidget);
    expect(find.text('Unassigned'), findsWidgets);
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
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
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

  testWidgets('assigned driver is rendered in booking detail', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'DRIVER_ASSIGNED',
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
              'allowedActions': ['REASSIGN_DRIVER'],
              'activeAssignment': {
                'driverDisplayName': 'Driver A',
                'driverStatus': 'AVAILABLE',
                'status': 'ASSIGNED',
                'assignedAt': '2026-06-30T23:14:47.000Z',
                'vehicle': {
                  'typeCode': 'SUV',
                  'plateNumber': 'LOCAL-SUV-D2',
                  'modelName': 'Local Test SUV',
                },
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Driver A'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsOneWidget);
    expect(find.text('SUV · LOCAL-SUV-D2 · Local Test SUV'), findsOneWidget);
    expect(find.text('2026-06-30T23:14:47.000Z'), findsOneWidget);
    expect(find.text('ASSIGNED'), findsOneWidget);
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
    final confirm = find.widgetWithText(ElevatedButton, 'Confirm Booking');
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Driver A'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.assignCalls, 1);
  });

  testWidgets('manual assignment refresh shows assigned driver', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      token: 'token',
      detailResponses: [
        {
          'bookingNumber': 'TX202607010001',
          'status': 'PENDING',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'activeAssignment': null,
          'allowedActions': ['ASSIGN_DRIVER'],
        },
        {
          'bookingNumber': 'TX202607010001',
          'status': 'DRIVER_ASSIGNED',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'activeAssignment': {
            'driverDisplayName': 'Driver A',
            'status': 'ASSIGNED',
          },
          'allowedActions': ['REASSIGN_DRIVER'],
        },
      ],
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
    await tester.tap(find.text('Assign driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Booking'));
    await tester.pumpAndSettle();
    expect(find.text('Driver A'), findsOneWidget);
  });

  testWidgets('reassign flow requires reason and calls API once', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      detailResponse: {
        'bookingNumber': 'TX202607010001',
        'status': 'DRIVER_ASSIGNED',
        'route': {
          'origin': {'address': 'BKK'},
          'destination': {'address': 'Pattaya'},
        },
        'customer': {'name': 'Kim', 'phone': '+66123456789'},
        'pricing': {
          'totalAmount': 1200,
          'currency': 'THB',
          'paymentMethod': 'PAY_DRIVER',
        },
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

  testWidgets('reassignment refresh updates displayed driver', (tester) async {
    final api = _FakeAdminApi(
      detailResponses: [
        {
          'bookingNumber': 'TX202607010001',
          'status': 'DRIVER_ASSIGNED',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'allowedActions': ['REASSIGN_DRIVER'],
          'activeAssignment': {
            'driverDisplayName': 'Old Driver',
            'status': 'ASSIGNED',
          },
        },
        {
          'bookingNumber': 'TX202607010001',
          'status': 'DRIVER_ASSIGNED',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'allowedActions': ['REASSIGN_DRIVER'],
          'activeAssignment': {
            'driverDisplayName': 'Driver A',
            'status': 'ASSIGNED',
          },
        },
      ],
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
    expect(find.text('Old Driver'), findsOneWidget);
    await tester.tap(find.text('Reassign driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Closer to pickup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Booking'));
    await tester.pumpAndSettle();
    expect(find.text('Driver A'), findsOneWidget);
    expect(find.text('Old Driver'), findsNothing);
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
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
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

  testWidgets('recommend drivers dialog shows candidates and excluded', (
    tester,
  ) async {
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

  testWidgets('assign recommended driver calls auto assign once', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      detailResponse: {
        'bookingNumber': 'TX202607010001',
        'status': 'CONFIRMED',
        'route': {
          'origin': {'address': 'BKK'},
          'destination': {'address': 'Pattaya'},
        },
        'customer': {'name': 'Kim', 'phone': '+66123456789'},
        'pricing': {
          'totalAmount': 1200,
          'currency': 'THB',
          'paymentMethod': 'PAY_DRIVER',
        },
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

  testWidgets('automatic assignment refresh shows assigned driver', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      detailResponses: [
        {
          'bookingNumber': 'TX202607010001',
          'status': 'CONFIRMED',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'activeAssignment': null,
          'allowedActions': ['RECOMMEND_DRIVERS'],
        },
        {
          'bookingNumber': 'TX202607010001',
          'status': 'DRIVER_ASSIGNED',
          'route': {
            'origin': {'address': 'BKK'},
            'destination': {'address': 'Pattaya'},
          },
          'customer': {'name': 'Kim', 'phone': '+66123456789'},
          'pricing': {
            'totalAmount': 1200,
            'currency': 'THB',
            'paymentMethod': 'PAY_DRIVER',
          },
          'activeAssignment': {
            'driverDisplayName': 'Driver A',
            'status': 'ASSIGNED',
          },
          'allowedActions': ['REASSIGN_DRIVER'],
        },
      ],
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
    expect(find.text('Driver A'), findsOneWidget);
  });

  testWidgets('recommend drivers shows error and retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRecommendDriversDialog(
              context: context,
              api: _FakeAdminApi(
                candidatesError: const AdminDispatchApiException(
                  'Server error',
                ),
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

  testWidgets('settlement pending without transfer slip hides confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: _settlementPendingDetail()),
          settlementApi: _FakeSettlementApi(
            detail: {
              'bookingNumber': 'TX202607010001',
              'commissionStatus': 'PENDING',
              'commissionAmount': 200,
              'currency': 'THB',
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settlement confirmation'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(
      find.text(
        'Payment can be confirmed after the driver uploads the transfer slip.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirm 200 THB received'), findsNothing);
    expect(find.text('View transfer slip'), findsNothing);
  });

  testWidgets('submitted transfer slip can be viewed and confirmed', (
    tester,
  ) async {
    final settlementApi = _FakeSettlementApi(
      detail: {
        'bookingNumber': 'TX202607010001',
        'commissionStatus': 'RECEIPT_SUBMITTED',
        'commissionAmount': 200,
        'currency': 'THB',
        'receiptUrl': '/api/v1/admin/settlements/TX202607010001/receipt',
        'receiptMetadata': {'mimeType': 'application/pdf'},
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: _settlementPendingDetail()),
          settlementApi: settlementApi,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transfer slip submitted'), findsOneWidget);
    expect(find.text('View transfer slip'), findsOneWidget);
    expect(find.text('Confirm 200 THB received'), findsOneWidget);

    await tester.ensureVisible(find.text('View transfer slip'));
    await tester.tap(find.text('View transfer slip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('transfer-slip.pdf'), findsOneWidget);
    expect(settlementApi.receiptCalls, 1);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Confirm 200 THB received'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(confirmButton.onPressed, isNotNull);
    confirmButton.onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.text('Confirm that 200 THB has been received from the driver?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(settlementApi.approveCalls, 1);
  });

  testWidgets('receipt-required approval race shows friendly guidance', (
    tester,
  ) async {
    final settlementApi = _FakeSettlementApi(
      detail: {
        'bookingNumber': 'TX202607010001',
        'commissionStatus': 'RECEIPT_SUBMITTED',
        'receiptUrl': '/api/v1/admin/settlements/TX202607010001/receipt',
      },
      approveError: const AdminSettlementApiException(
        'Receipt must be submitted before approval',
        statusCode: 409,
        errorCode: 'RECEIPT_REQUIRED',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: _settlementPendingDetail()),
          settlementApi: settlementApi,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final confirmButton = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Confirm 200 THB received'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(confirmButton.onPressed, isNotNull);
    confirmButton.onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text(
        'Payment can be confirmed after the driver uploads the transfer slip.',
      ),
      findsOneWidget,
    );
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
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
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
                  'unavailableReason':
                      'Dropoff QR reissue requires status PICKED_UP',
                },
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QR management'), findsNothing);
    expect(find.text('Reissue boarding QR'), findsNothing);
  });

  testWidgets('hides internal QR configuration when reissue disabled', (
    tester,
  ) async {
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
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
              'allowedActions': [],
              'devQrTools': {
                'qrReissueEnabled': false,
                'disabledReason':
                    'Set ALLOW_DEV_QR_REISSUE=true on the backend and restart',
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
    expect(find.text('QR management'), findsNothing);
    expect(find.text('Reissue boarding QR'), findsNothing);
  });

  testWidgets('dev QR reissue is hidden from admin booking detail', (
    tester,
  ) async {
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
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
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
    expect(find.text('Reissue boarding QR'), findsNothing);
    expect(find.text('QR management'), findsNothing);
  });

  testWidgets('dispatch queue has no horizontal overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDispatchQueuePage(
          api: _FakeAdminApi(
            token: 'admin-token',
            bookingsResponse: {
              'page': 1,
              'total': 1,
              'items': [
                {
                  'bookingNumber': 'TX202607010001',
                  'status': 'CONFIRMED',
                  'serviceTypeName': 'Airport Pickup',
                  'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
                  'originAddress':
                      'Suvarnabhumi Airport Terminal 1 International Arrivals',
                  'destinationAddress':
                      'Pattaya Beach Road Hotel Resort Thailand',
                  'assignmentState': 'UNASSIGNED',
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TX202607010001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin booking detail shows low rating review', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(
            detailResponse: {
              'bookingNumber': 'TX202607010001',
              'status': 'COMPLETED',
              'serviceType': {'name': 'Airport Pickup'},
              'route': {
                'origin': {'address': 'BKK'},
                'destination': {'address': 'Pattaya'},
              },
              'customer': {'name': 'Kim', 'phone': '+66123456789'},
              'pricing': {
                'totalAmount': 1200,
                'currency': 'THB',
                'paymentMethod': 'PAY_DRIVER',
              },
              'allowedActions': [],
              'customerReview': {
                'reviewId': 9,
                'rating': 2,
                'tags': ['LATE_ARRIVAL', 'UNFRIENDLY_SERVICE'],
                'comment': 'Driver was late and rude.',
                'lowRating': true,
                'createdAt': '2026-07-02 10:00:00',
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Low rating requires review'), findsOneWidget);
    expect(find.text('Customer review'), findsOneWidget);
    expect(find.text('Late arrival'), findsOneWidget);
    expect(find.text('Driver was late and rude.'), findsOneWidget);
  });

  testWidgets('admin detail follows operations workspace section order', (
    tester,
  ) async {
    final detail = {
      ..._settlementPendingDetail(),
      'scheduledPickupAt': '2026-07-11 09:30:00',
      'serviceType': {'code': 'AIRPORT_TO_CITY', 'name': 'Airport transfer'},
      'vehicle': {'typeName': 'SUV'},
      'passengers': {'adults': 2, 'children': 0, 'infants': 0},
      'luggage': {'carriers20Inch': 1, 'carriers24InchPlus': 0, 'golfBags': 0},
      'operations': {'adminUnreadCount': 3},
      'statusHistory': [
        {
          'fromStatus': 'PICKED_UP',
          'toStatus': 'SETTLEMENT_PENDING',
          'changedByRole': 'DRIVER',
          'createdAt': '2026-07-11 12:30:00',
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: detail),
          settlementApi: _FakeSettlementApi(
            detail: const {'commissionStatus': 'DUE'},
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final labels = [
      'Customer information',
      'Trip information',
      'Driver and vehicle',
      'Fare and settlement',
      'Customer and driver chat',
      'Status history',
      'Technical information',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Customer chat unread'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Customer review'), findsNothing);
    expect(find.text('Raw booking status'), findsNothing);
  });

  testWidgets(
    'admin detail shows one primary assign CTA and no 320px overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminBookingDetailPage(
            bookingNumber: 'TX202607010001',
            api: _FakeAdminApi(),
            onChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assign driver'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('admin detail operation labels are localized for KO EN and TH', () {
    expect(AppLocalizations('ko').t('admin_detail_technical'), '기술 정보');
    expect(
      AppLocalizations('en').t('admin_detail_technical'),
      'Technical information',
    );
    expect(
      AppLocalizations('th').t('admin_detail_technical'),
      'ข้อมูลทางเทคนิค',
    );
  });
}
