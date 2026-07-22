import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_booking_detail_page.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/utils/admin_operations_ux.dart';
import 'package:frontend/features/admin_dispatch/widgets/recommend_drivers_dialog.dart';
import 'package:frontend/features/admin_settlement/services/admin_settlement_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int addNoteCalls = 0;
  int archiveCalls = 0;
  int restoreCalls = 0;
  List<Map<String, dynamic>> notes = [];
  List<String> lastArchivedBookings = [];
  List<String> lastRestoredBookings = [];
  Object? addNoteError;
  String? lastAssignmentState;
  String? lastStatus;
  String? lastView;
  String? lastSearch;
  String? lastServiceDateFrom;
  String? lastServiceDateTo;
  bool? lastArchived;
  bool? lastUnassigned;
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
    bool? archived,
    int page = 1,
    int limit = 20,
  }) async {
    lastAssignmentState = assignmentState;
    lastStatus = status;
    lastView = view;
    lastSearch = search;
    lastServiceDateFrom = serviceDateFrom;
    lastServiceDateTo = serviceDateTo;
    lastArchived = archived;
    lastUnassigned = unassigned;
    if (bookingsError != null) throw bookingsError!;
    return bookingsResponse ?? {'page': 1, 'total': 0, 'items': []};
  }

  @override
  Future<Map<String, dynamic>> archiveBookings(
    List<String> bookingNumbers,
  ) async {
    archiveCalls += 1;
    lastArchivedBookings = bookingNumbers;
    return {
      'archived': bookingNumbers.length,
      'items': bookingNumbers
          .map((bookingNumber) => {'bookingNumber': bookingNumber})
          .toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> restoreBookings(
    List<String> bookingNumbers,
  ) async {
    restoreCalls += 1;
    lastRestoredBookings = bookingNumbers;
    return {
      'restored': bookingNumbers.length,
      'items': bookingNumbers
          .map((bookingNumber) => {'bookingNumber': bookingNumber})
          .toList(),
    };
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
  Future<Map<String, dynamic>> listBookingNotes(
    String bookingNumber, {
    int page = 1,
    int limit = 20,
  }) async => {
    'page': page,
    'page_size': limit,
    'total': notes.length,
    'items': notes,
  };

  @override
  Future<Map<String, dynamic>> addBookingNote(
    String bookingNumber,
    String text,
  ) async {
    addNoteCalls += 1;
    if (addNoteError != null) throw addNoteError!;
    final note = {
      'id': notes.length + 1,
      'text': text,
      'author': {'id': 1, 'name': 'Admin A'},
      'createdAt': '2026-07-12 10:30:00',
    };
    notes.add(note);
    return note;
  }

  @override
  Future<List<dynamic>> listDrivers({bool? archived}) async {
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
  _FakeSettlementApi({required this.detail, this.approveError, this.loadError});

  final Map<String, dynamic> detail;
  final Object? approveError;
  final Object? loadError;
  int getSettlementCalls = 0;
  int approveCalls = 0;
  int manualApproveCalls = 0;
  int receiptCalls = 0;
  String? manualApproveNote;

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    getSettlementCalls += 1;
    if (loadError != null) throw loadError!;
    return detail;
  }

  @override
  Future<Map<String, dynamic>> approve(String bookingNumber) async {
    approveCalls += 1;
    if (approveError != null) throw approveError!;
    return {...detail, 'commissionStatus': 'APPROVED'};
  }

  @override
  Future<Map<String, dynamic>> manualApprove(
    String bookingNumber,
    String note,
  ) async {
    manualApproveCalls += 1;
    manualApproveNote = note;
    return {
      ...detail,
      'commissionStatus': 'APPROVED',
      'approval': {'mode': 'MANUAL_WITHOUT_RECEIPT', 'note': note},
    };
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

Map<String, dynamic> _completedDueDetail() => {
  ..._settlementPendingDetail(),
  'status': 'COMPLETED',
  'commissionStatus': 'DUE',
  'updatedAt': '2026-07-16 10:00:00',
  'statusHistory': [
    {
      'fromStatus': 'PICKED_UP',
      'toStatus': 'COMPLETED',
      'changedByRole': 'DRIVER',
      'createdAt': '2026-07-16 09:00:00',
      'memo': 'Dropoff completed',
    },
  ],
};

Map<String, dynamic> _queueItem(String bookingNumber) => {
  'bookingNumber': bookingNumber,
  'status': 'PENDING',
  'serviceType': {'code': 'AIRPORT_PICKUP', 'name': 'Airport Pickup'},
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

  testWidgets(
    'maps backend validation detail instead of showing generic message',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDispatchQueuePage(
            api: _FakeAdminApi(
              token: 'token',
              bookingsError: const AdminDispatchApiException(
                'Validation failed',
                errorCode: 'VALIDATION_ERROR',
                errors: [
                  AdminDispatchApiErrorDetail(
                    field: 'serviceDateTo',
                    type: 'date.range',
                    source: 'query',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Validation failed'), findsNothing);
      expect(
        find.text('The end date cannot be earlier than the start date.'),
        findsOneWidget,
      );
    },
  );

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
    expect(api.lastUnassigned, isNull);
  });

  testWidgets('unassigned list separates total and visible item count', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {
        'page': 1,
        'total': 5,
        'items': [_queueItem('TX202607160001'), _queueItem('TX202607160002')],
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('All unassigned 5'), findsOneWidget);
    expect(find.textContaining('Showing 2'), findsOneWidget);
  });

  test(
    'date filter API uses YYYY-MM-DD query names and omits null dates',
    () async {
      SharedPreferences.setMockInitialValues({'admin_access_token': 'token'});
      late Uri captured;
      final api = AdminDispatchApiService(
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          captured = request.url;
          return http.Response(
            '{"success":true,"data":{"page":1,"total":0,"items":[]}}',
            200,
          );
        }),
      );

      await api.listBookings(
        view: 'all',
        search: 'TX202607160001',
        serviceDateFrom: '2026-07-22',
        serviceDateTo: '2026-07-24',
        page: 1,
        limit: 20,
      );

      expect(captured.path, '/api/v1/admin/bookings');
      expect(captured.queryParameters['view'], 'all');
      expect(captured.queryParameters['search'], 'TX202607160001');
      expect(captured.queryParameters['serviceDateFrom'], '2026-07-22');
      expect(captured.queryParameters['serviceDateTo'], '2026-07-24');
      expect(captured.queryParameters['dateFrom'], isNull);
      expect(captured.queryParameters['dateTo'], isNull);
    },
  );

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

  test('summary card keys map to matching booking list views', () {
    expect(
      AdminOperationsUx.viewForSummaryCard('needsAction'),
      AdminBookingView.needsAction,
    );
    expect(
      AdminOperationsUx.viewForSummaryCard('unassigned'),
      AdminBookingView.all,
    );
    expect(
      AdminOperationsUx.viewForSummaryCard('today'),
      AdminBookingView.today,
    );
    expect(
      AdminOperationsUx.viewForSummaryCard('inProgress'),
      AdminBookingView.inProgress,
    );
    expect(
      AdminOperationsUx.viewForSummaryCard('settlementPending'),
      AdminBookingView.settlement,
    );
    expect(
      AdminOperationsUx.viewForSummaryCard('issues'),
      AdminBookingView.issues,
    );
  });

  test(
    'route context labels explain service direction without swapping data',
    () {
      final ko = AppLocalizations('ko');
      final en = AppLocalizations('en');
      final th = AppLocalizations('th');

      expect(
        AdminOperationsUx.routeContextLabel(ko, 'AIRPORT_PICKUP'),
        '공항 → 목적지',
      );
      expect(
        AdminOperationsUx.routeContextLabel(en, 'AIRPORT_DROPOFF'),
        'Origin → Airport',
      );
      expect(
        AdminOperationsUx.routeContextLabel(th, 'CITY_TRANSFER'),
        'จุดต้นทาง → จุดหมาย',
      );
    },
  );

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

  testWidgets('archives selected bookings after confirmation', (tester) async {
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {
        'page': 1,
        'total': 1,
        'items': [_queueItem('TX202607010001')],
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide test bookings (1)'));
    await tester.pumpAndSettle();

    expect(
      find.text('Hide the selected bookings as test data?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Hide test bookings').last);
    await tester.pumpAndSettle();

    expect(api.archiveCalls, 1);
    expect(api.lastArchivedBookings, ['TX202607010001']);
  });

  testWidgets('archived view requests hidden bookings and restores them', (
    tester,
  ) async {
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {
        'page': 1,
        'total': 1,
        'items': [
          {
            ..._queueItem('TX202607010001'),
            'archive': {'isArchived': true, 'reason': 'TEST_DATA'},
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show hidden bookings'));
    await tester.pumpAndSettle();

    expect(api.lastArchived, isTrue);
    expect(find.text('Archived/Test'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(api.restoreCalls, 1);
    expect(api.lastRestoredBookings, ['TX202607010001']);
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

  testWidgets('queue card uses review-and-act CTA and expands extra reasons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = {
      ..._queueItem('TX202607010001'),
      'operations': {
        'severity': 'URGENT',
        'primaryActionReason': 'PICKUP_OVERDUE_UNASSIGNED',
        'primaryCta': 'ASSIGN_DRIVER',
        'actionReasons': [
          'PICKUP_OVERDUE_UNASSIGNED',
          'CUSTOMER_INQUIRY',
          'STATUS_STALE',
        ],
        'extraActionReasonCount': 2,
      },
      'primaryCta': 'ASSIGN_DRIVER',
    };
    final api = _FakeAdminApi(
      token: 'token',
      bookingsResponse: {
        'page': 1,
        'total': 1,
        'items': [item],
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDispatchQueuePage(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pickup overdue · unassigned'), findsOneWidget);
    expect(find.text('2 more reasons'), findsOneWidget);
    expect(find.text('Review & act'), findsOneWidget);
    expect(find.text('Assign driver'), findsNothing);
    expect(find.text('CUSTOMER_INQUIRY'), findsNothing);

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Customer inquiry pending'), findsOneWidget);
    expect(find.textContaining('No recent status change'), findsOneWidget);

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(api.assignCalls, 0);
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
    expect(find.text('AVAILABLE'), findsWidgets);
    expect(find.text('SUV'), findsWidgets);
    expect(find.text('LOCAL-SUV-D2'), findsOneWidget);
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
    await tester.enterText(find.byType(TextField).last, 'Closer to pickup');
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
    await tester.enterText(find.byType(TextField).last, 'Closer to pickup');
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

  testWidgets(
    'settlement pending without transfer slip allows manual approval',
    (tester) async {
      final settlementApi = _FakeSettlementApi(
        detail: {
          'bookingNumber': 'TX202607010001',
          'commissionStatus': 'PENDING',
          'commissionAmount': 200,
          'currency': 'THB',
          'canManualApprove': true,
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

      expect(find.text('Settlement confirmation'), findsOneWidget);
      expect(find.text('Settlement required'), findsWidgets);
      expect(
        find.text(
          'Payment can be confirmed after the driver uploads the transfer slip.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm 200 THB received'), findsNothing);
      expect(find.text('View transfer slip'), findsNothing);
      expect(find.text('Manual settlement approval'), findsWidgets);

      await tester.ensureVisible(find.text('Manual settlement approval').last);
      await tester.tap(find.text('Manual settlement approval').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No transfer slip has been uploaded'),
        findsOneWidget,
      );

      await tester.tap(find.text('Confirm approval'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter an approval note.'), findsOneWidget);
      expect(settlementApi.manualApproveCalls, 0);

      await tester.enterText(
        find.byType(TextField).last,
        'Verified bank deposit manually',
      );
      await tester.tap(find.text('Confirm approval'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(settlementApi.manualApproveCalls, 1);
      expect(settlementApi.manualApproveNote, 'Verified bank deposit manually');
    },
  );

  testWidgets('submitted transfer slip can be viewed and confirmed', (
    tester,
  ) async {
    final settlementApi = _FakeSettlementApi(
      detail: {
        'bookingNumber': 'TX202607010001',
        'commissionStatus': 'RECEIPT_SUBMITTED',
        'receiptStatus': 'RECEIPT_SUBMITTED',
        'receiptFileId': 42,
        'commissionAmount': 200,
        'currency': 'THB',
        'canApprove': true,
        'receiptSubmittedAt': '2026-07-16 12:00:00',
        'receiptUrl': '/api/v1/admin/settlements/TX202607010001/receipt',
        'receiptMetadata': {
          'mimeType': 'application/pdf',
          'originalFilename': 'receipt.pdf',
          'fileSize': 2048,
        },
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

    expect(find.text('Transfer slip submitted'), findsWidgets);
    expect(find.text('View transfer slip'), findsOneWidget);
    expect(find.text('Confirm 200 THB received'), findsOneWidget);
    expect(find.text('receipt.pdf'), findsOneWidget);
    expect(find.text('application/pdf'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);

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

  testWidgets('completed due booking shows settlement info without approval', (
    tester,
  ) async {
    final settlementApi = _FakeSettlementApi(
      detail: {
        'bookingNumber': 'TX202607010001',
        'status': 'COMPLETED',
        'commissionStatus': 'PENDING',
        'receiptStatus': 'NONE',
        'commissionAmount': 200,
        'currency': 'THB',
        'canApprove': false,
        'canManualApprove': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: _completedDueDetail()),
          settlementApi: settlementApi,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(settlementApi.getSettlementCalls, 1);
    expect(find.text('Operations summary'), findsOneWidget);
    expect(find.text('Settlement confirmation'), findsOneWidget);
    expect(find.text('Settlement required'), findsWidgets);
    expect(find.text('Transfer slip missing'), findsWidgets);
    expect(
      find.textContaining(
        'The trip is completed, but the booking has not moved',
      ),
      findsWidgets,
    );
    expect(find.text('Confirm 200 THB received'), findsNothing);
    expect(find.text('Manual settlement approval'), findsNothing);
  });

  testWidgets('settlement load failure keeps booking detail visible', (
    tester,
  ) async {
    final settlementApi = _FakeSettlementApi(
      detail: const {},
      loadError: const AdminSettlementApiException('Settlement unavailable'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: _completedDueDetail()),
          settlementApi: settlementApi,
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operations summary'), findsOneWidget);
    expect(find.text('Fare and settlement'), findsOneWidget);
    expect(find.text('Settlement unavailable'), findsOneWidget);
    expect(find.text('Retry settlement'), findsOneWidget);
    expect(settlementApi.getSettlementCalls, 1);
  });

  testWidgets('rejected transfer slip reason is highlighted', (tester) async {
    final settlementApi = _FakeSettlementApi(
      detail: {
        'bookingNumber': 'TX202607010001',
        'status': 'SETTLEMENT_PENDING',
        'commissionStatus': 'REJECTED',
        'receiptStatus': 'REJECTED',
        'commissionAmount': 200,
        'currency': 'THB',
        'rejectionReason': 'Amount cannot be verified.',
        'canApprove': false,
        'canManualApprove': false,
        'reviewHistory': [
          {'action': 'REJECTED', 'reviewedAt': '2026-07-16T12:30:00Z'},
        ],
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

    expect(find.text('Transfer slip rejected'), findsWidgets);
    expect(find.textContaining('Amount cannot be verified.'), findsOneWidget);
    expect(find.text('Confirm 200 THB received'), findsNothing);
  });

  testWidgets('settlement detail CTA scrolls to settlement section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = {
      ..._settlementPendingDetail(),
      'operations': {
        'primaryActionReason': 'RECEIPT_MISSING',
        'primaryCta': 'SETTLEMENT_DETAIL',
        'actionReasons': ['RECEIPT_MISSING'],
      },
      'primaryCta': 'SETTLEMENT_DETAIL',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: detail),
          settlementApi: _FakeSettlementApi(
            detail: const {
              'bookingNumber': 'TX202607010001',
              'commissionStatus': 'DUE',
              'commissionAmount': 200,
              'currency': 'THB',
            },
          ),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settlement detail'));
    await tester.pumpAndSettle();
    expect(find.text('Settlement confirmation'), findsOneWidget);
  });

  testWidgets('review rating CTA scrolls to customer review section', (
    tester,
  ) async {
    final detail = {
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
      'operations': {
        'primaryActionReason': 'LOW_RATING',
        'primaryCta': 'REVIEW_RATING',
        'actionReasons': ['LOW_RATING'],
      },
      'primaryCta': 'REVIEW_RATING',
      'customerReview': {
        'reviewId': 9,
        'rating': 2,
        'tags': ['LATE_ARRIVAL'],
        'comment': 'Driver was late.',
        'lowRating': true,
        'createdAt': '2026-07-02 10:00:00',
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: detail),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review rating'));
    await tester.pumpAndSettle();
    expect(find.text('Customer review'), findsOneWidget);
  });

  testWidgets('check status CTA keeps operations summary visible', (
    tester,
  ) async {
    final detail = {
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
        'driverStatus': 'AVAILABLE',
        'status': 'ASSIGNED',
      },
      'allowedActions': ['REASSIGN_DRIVER'],
      'operations': {
        'primaryActionReason': 'STATUS_STALE',
        'primaryCta': 'CHECK_STATUS',
        'actionReasons': ['STATUS_STALE'],
      },
      'primaryCta': 'CHECK_STATUS',
      'statusHistory': [
        {
          'fromStatus': 'DRIVER_ASSIGNED',
          'toStatus': 'ON_ROUTE',
          'changedByRole': 'DRIVER',
          'createdAt': '2026-07-11 10:30:00',
          'memo': 'Driver started route',
        },
        {
          'fromStatus': 'CONFIRMED',
          'toStatus': 'DRIVER_ASSIGNED',
          'changedByRole': 'ADMIN',
          'createdAt': '2026-07-11 09:30:00',
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeAdminApi(detailResponse: detail),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operations summary'), findsOneWidget);
    expect(find.text('Current status'), findsOneWidget);
    expect(find.text('Last status change'), findsOneWidget);
    expect(find.text('Current status duration'), findsOneWidget);
    expect(find.text('Driver A · ASSIGNED'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsWidgets);
    expect(
      find.text(
        'The booking status has not changed for a long time. Check the current driver and trip status.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Driver started route'), findsWidgets);
    expect(find.text('Driver'), findsWidgets);

    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    expect(find.text('Operations summary'), findsOneWidget);

    final onRouteY = tester.getTopLeft(find.text('On the way').first).dy;
    final assignedY = tester.getTopLeft(find.text('Driver Assigned').last).dy;
    expect(onRouteY, lessThan(assignedY));
  });

  testWidgets('receipt-required approval race shows friendly guidance', (
    tester,
  ) async {
    final settlementApi = _FakeSettlementApi(
      detail: {
        'bookingNumber': 'TX202607010001',
        'commissionStatus': 'RECEIPT_SUBMITTED',
        'receiptStatus': 'RECEIPT_SUBMITTED',
        'canApprove': true,
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
    expect(find.text('Submitted at'), findsOneWidget);
    expect(find.text('2026-07-02 10:00:00'), findsOneWidget);
  });

  testWidgets(
    'admin booking detail shows empty state for blank review comment',
    (tester) async {
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
                'customerReview': {
                  'reviewId': 10,
                  'rating': 5,
                  'tags': ['FRIENDLY'],
                  'comment': '',
                  'lowRating': false,
                  'createdAt': '2026-07-02 11:00:00',
                },
              },
            ),
            onChanged: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Customer review'), findsOneWidget);
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('Friendly'), findsOneWidget);
      expect(find.text('No written review was provided.'), findsOneWidget);
      expect(find.text('2026-07-02 11:00:00'), findsOneWidget);
    },
  );

  testWidgets('admin booking detail renders review comment as plain text', (
    tester,
  ) async {
    const comment =
        'Line one\nLine two with <script>alert("x")</script> and **markdown**';

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
              'customerReview': {
                'reviewId': 11,
                'rating': 2,
                'tags': ['OTHER_ISSUE'],
                'comment': comment,
                'lowRating': true,
                'createdAt': '2026-07-02 12:00:00',
              },
            },
          ),
          onChanged: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text(comment), findsOneWidget);
    expect(find.textContaining('<script>'), findsOneWidget);
    expect(find.textContaining('**markdown**'), findsOneWidget);
  });

  testWidgets(
    'admin booking detail long review comment has no 320px overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final longComment = 'https://example.com/${'a' * 480}';

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
                'customerReview': {
                  'reviewId': 12,
                  'rating': 5,
                  'tags': [],
                  'comment': longComment,
                  'lowRating': false,
                  'createdAt': '2026-07-02 13:00:00',
                },
              },
            ),
            onChanged: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('https://example.com/'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('internal notes show empty state and disable blank submit', (
    tester,
  ) async {
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
    expect(find.text('Internal notes'), findsOneWidget);
    expect(find.text('Visible to administrators only.'), findsOneWidget);
    expect(find.text('No internal notes yet.'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Add note'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('internal note success appends item and clears input', (
    tester,
  ) async {
    final api = _FakeAdminApi();
    api.notes.add({
      'id': 1,
      'text': 'Existing note',
      'author': {'id': 1, 'name': 'Admin A'},
      'createdAt': '2026-07-12 09:00:00',
    });
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
    expect(find.text('Existing note'), findsOneWidget);
    expect(find.textContaining('Admin A'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin-note-input')),
      'New operational note',
    );
    await tester.pump();
    final addButton = find.widgetWithText(ElevatedButton, 'Add note');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(api.addNoteCalls, 1);
    expect(find.text('New operational note'), findsOneWidget);
    expect(find.text('Add an operational note'), findsOneWidget);
  });

  testWidgets('internal note failure keeps input for retry', (tester) async {
    final api = _FakeAdminApi()
      ..addNoteError = const AdminDispatchApiException('Save failed');
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
    await tester.enterText(
      find.byKey(const Key('admin-note-input')),
      'Keep this text',
    );
    await tester.pump();
    final addButton = find.widgetWithText(ElevatedButton, 'Add note');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(find.text('Keep this text'), findsOneWidget);
  });

  test('internal note labels are localized for KO EN and TH', () {
    expect(AppLocalizations('ko').t('admin_notes_title'), '내부 메모');
    expect(AppLocalizations('en').t('admin_notes_title'), 'Internal notes');
    expect(AppLocalizations('th').t('admin_notes_title'), 'บันทึกภายใน');
  });
}
