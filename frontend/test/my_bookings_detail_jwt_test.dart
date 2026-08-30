import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/services/customer_bookings_api_service.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:frontend/features/booking/widgets/booking_notification_section.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/features/driver_location/models/driver_location.dart';
import 'package:frontend/features/driver_location/services/driver_location_api_service.dart';
import 'package:frontend/features/driver_location/services/driver_location_socket_service.dart';
import 'package:frontend/features/driver_location/widgets/guest_driver_tracking_section.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';

GuestBookingLookupResult _myBookingDetail({
  String status = 'DRIVER_ASSIGNED',
  bool canReview = false,
  bool canCancel = true,
}) {
  return GuestBookingLookupResult.fromCustomerBookingsApiJson({
    'bookingId': 10,
    'bookingNumber': 'TX202607010001',
    'status': status,
    'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
    'serviceType': {'code': 'AIRPORT_PICKUP', 'name': 'Airport Pickup'},
    'route': {
      'origin': {'code': 'BKK', 'address': 'BKK Airport'},
      'destination': {'code': 'PATTAYA', 'address': 'Pattaya Hotel'},
    },
    'pricing': {
      'totalAmount': 1500,
      'currency': 'THB',
      'paymentMethod': 'PAY_DRIVER',
    },
    'vehicle': {'typeCode': 'SUV', 'typeName': 'SUV', 'count': 1},
    'assignedDriver': {
      'name': 'Driver A',
      'phone': '+66 80 000 0000',
      'vehicle': {
        'typeCode': 'SUV',
        'typeName': 'SUV',
        'plateNumber': '1กข1234',
        'color': 'Black',
      },
    },
    'capabilities': {
      'notificationsAvailable': true,
      'trackingAvailable': true,
      'reviewAvailable': canReview,
      'cancelAvailable': canCancel,
    },
    'canReview': canReview,
    'canCancel': canCancel,
    'cancellationDeadline': '2026-07-01T07:30:00+07:00',
    'guestAccess': {'token': null, 'expiresAt': null},
  });
}

class _FakeCustomerBookingsApiService extends CustomerBookingsApiService {
  _FakeCustomerBookingsApiService(this._booking);

  final GuestBookingLookupResult _booking;
  int findCalls = 0;

  @override
  Future<GuestBookingLookupResult> findMyBookingByNumber(
    String bookingNumber,
  ) async {
    findCalls += 1;
    if (bookingNumber.trim().toUpperCase() != _booking.bookingNumber) {
      throw const CustomerBookingsApiException('Booking not found', statusCode: 404);
    }
    return _booking.copyWith(status: 'ON_ROUTE');
  }
}

class _FakeBookingNotificationApi extends BookingNotificationApi {
  _FakeBookingNotificationApi({this.customerTokenUsed = false});

  bool customerTokenUsed;
  String? lastCustomerToken;
  String? lastGuestToken;

  @override
  Future<Map<String, dynamic>> listForBooking({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    lastCustomerToken = customerAccessToken;
    lastGuestToken = guestAccessToken;
    if (customerAccessToken != null && customerAccessToken.isNotEmpty) {
      customerTokenUsed = true;
    }
    return {
      'items': [
        {'title': 'Driver assigned', 'body': 'Your driver is on the way', 'read': false},
      ],
    };
  }
}

class _FakeReviewApi extends BookingReviewApi {
  _FakeReviewApi();

  String? lastCustomerToken;
  String? lastGuestToken;

  @override
  Future<Map<String, dynamic>> submitReview({
    required String bookingNumber,
    required int rating,
    List<String>? tags,
    String? comment,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    lastCustomerToken = customerAccessToken;
    lastGuestToken = guestAccessToken;
    return {
      'eligible': true,
      'submitted': true,
      'rating': rating,
      'tags': tags ?? [],
      'comment': comment,
    };
  }
}

class _FakeMyBookingsTrackingApi extends DriverLocationApiService {
  _FakeMyBookingsTrackingApi(this.result);

  final GuestDriverLocationResult result;
  int calls = 0;
  String? lastCustomerToken;
  bool lastUseCustomerAuth = false;

  @override
  Future<GuestDriverLocationResult> getGuestDriverLocation({
    required int bookingId,
    String guestAccessToken = '',
    String? customerAccessToken,
    bool useCustomerAuth = false,
  }) async {
    calls += 1;
    lastCustomerToken = customerAccessToken;
    lastUseCustomerAuth = useCustomerAuth;
    return result;
  }
}

class _FakeMyBookingsTrackingSocket extends DriverLocationSocketService {
  String? connectedAccessToken;

  @override
  Future<void> connect({String? accessToken, String? guestAccessToken}) async {
    connectedAccessToken = accessToken;
  }

  @override
  void subscribeGuest(int bookingId) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AuthTokenStorage.accessTokenKey: 'customer-jwt',
      AuthTokenStorage.refreshTokenKey: 'refresh-token',
      AuthTokenStorage.userJsonKey: jsonEncode({
        'id': 42,
        'email': 'guest@example.com',
        'role': 'CUSTOMER',
        'name': 'Minji',
        'phone': null,
        'locale': 'ko',
        'isActive': true,
      }),
    });
  });

  testWidgets('fromMyBookings shows driver phone without guest token', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          fromMyBookings: true,
          enableCustomerTools: true,
          initialResult: _myBookingDetail(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+66 80 000 0000'), findsWidgets);
  });

  testWidgets('fromMyBookings hides driver phone until customer JWT loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          fromMyBookings: true,
          enableCustomerTools: true,
          initialResult: _myBookingDetail(),
          tokenStorage: DelayedAuthTokenStorage(
            const Duration(milliseconds: 200),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('+66 80 000 0000'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('+66 80 000 0000'), findsWidgets);
  });

  testWidgets('fromMyBookings hides notifications until customer JWT loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          fromMyBookings: true,
          enableCustomerTools: true,
          initialResult: _myBookingDetail(status: 'COMPLETED', canReview: true),
          tokenStorage: DelayedAuthTokenStorage(
            const Duration(milliseconds: 200),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BookingNotificationSection), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(BookingNotificationSection), findsOneWidget);
  });

  testWidgets('fromMyBookings refresh uses customer bookings API', (
    tester,
  ) async {
    final booking = _myBookingDetail();
    final api = _FakeCustomerBookingsApiService(booking);

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          fromMyBookings: true,
          enableCustomerTools: true,
          initialResult: booking,
          customerBookingsApiService: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('guest_lookup_refresh')));
    await tester.pumpAndSettle();

    expect(api.findCalls, 1);
    expect(find.textContaining('guest_lookup_refresh_needs_phone'), findsNothing);
  });

  testWidgets('fromMyBookings notifications section uses customer JWT', (
    tester,
  ) async {
    final fakeApi = _FakeBookingNotificationApi();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            bookingId: 10,
            customerAccessToken: 'customer-jwt',
            useCustomerPushRegistration: true,
            api: fakeApi,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(fakeApi.customerTokenUsed, isTrue);
    expect(fakeApi.lastCustomerToken, 'customer-jwt');
    expect(find.text('Driver assigned'), findsOneWidget);
  });

  testWidgets('guest lookup path still hides driver phone without guest token', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          enableCustomerTools: true,
          initialResult: _myBookingDetail(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+66 80 000 0000'), findsNothing);
  });

  testWidgets('fromMyBookings shows tracking section and uses customer JWT', (
    tester,
  ) async {
    final trackingApi = _FakeMyBookingsTrackingApi(
      GuestDriverLocationResult(
        available: true,
        bookingStatus: 'ON_ROUTE',
        driver: DriverLocation(
          driverId: 0,
          displayName: 'Driver A',
          vehicle: 'SUV / 1กข1234',
          latitude: 12.9,
          longitude: 100.8,
          stale: false,
        ),
      ),
    );
    final trackingSocket = _FakeMyBookingsTrackingSocket();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          fromMyBookings: true,
          enableCustomerTools: true,
          initialResult: _myBookingDetail(status: 'ON_ROUTE'),
          trackingBuilder: (result) => GuestDriverTrackingSection(
            bookingId: result.bookingId!,
            guestAccessToken: result.guestAccessToken,
            bookingStatus: result.status,
            useCustomerAuth: true,
            customerAccessToken: 'customer-jwt',
            api: trackingApi,
            socket: trackingSocket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver location'), findsOneWidget);
    expect(trackingApi.calls, greaterThanOrEqualTo(1));
    expect(trackingApi.lastCustomerToken, 'customer-jwt');
    expect(trackingApi.lastUseCustomerAuth, isTrue);
    expect(trackingSocket.connectedAccessToken, 'customer-jwt');
  });

  testWidgets('fromMyBookings renders default tracking section without guest token', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: GuestBookingLookupPage(
          fromMyBookings: true,
          enableCustomerTools: true,
          initialResult: _myBookingDetail(status: 'DRIVER_ASSIGNED'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GuestDriverTrackingSection), findsOneWidget);
    final section = tester.widget<GuestDriverTrackingSection>(
      find.byType(GuestDriverTrackingSection),
    );
    expect(section.useCustomerAuth, isTrue);
    expect(section.customerAccessToken, 'customer-jwt');
    expect(section.guestAccessToken, isEmpty);
  });

  test('cancelBooking uses JWT when guest token is missing', () async {
    String? authHeader;
    final service = GuestBookingLookupService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookingNumber': 'TX202607010001',
              'status': 'CANCELLED',
              'canCancel': false,
              'cancellationBlockedReason': 'ALREADY_CANCELLED',
            },
          }),
          200,
        );
      }),
    );

    final booking = _myBookingDetail();
    final updated = await service.cancelBooking(
      booking: booking,
      customerAccessToken: 'customer-jwt',
    );

    expect(authHeader, 'Bearer customer-jwt');
    expect(updated.status, 'CANCELLED');
  });

  test('review submit passes customerAccessToken when provided', () async {
    final api = _FakeReviewApi();
    await api.submitReview(
      bookingNumber: 'TX202607010001',
      rating: 5,
      customerAccessToken: 'customer-jwt',
    );

    expect(api.lastCustomerToken, 'customer-jwt');
    expect(api.lastGuestToken, isNull);
  });
}
