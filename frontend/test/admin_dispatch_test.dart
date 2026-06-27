import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_booking_detail_page.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';

class _FakeAdminApi extends AdminDispatchApiService {
  _FakeAdminApi({
    this.token,
    this.bookingsResponse,
    this.bookingsError,
    this.detailResponse,
    this.driversResponse,
    this.assignCalls = 0,
    this.reassignCalls = 0,
    this.lastAssignmentState,
    this.lastStatus,
  });

  final String? token;
  final Map<String, dynamic>? bookingsResponse;
  final Object? bookingsError;
  final Map<String, dynamic>? detailResponse;
  final List<dynamic>? driversResponse;
  int assignCalls;
  int reassignCalls;
  String? lastAssignmentState;
  String? lastStatus;

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
}
