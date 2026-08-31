import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/customer_session.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/pages/my_bookings_page.dart';
import 'package:frontend/features/booking/services/customer_bookings_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';

class _FakeCustomerBookingsApiService extends CustomerBookingsApiService {
  _FakeCustomerBookingsApiService(this._result);

  final CustomerBookingsPageResult _result;

  @override
  Future<CustomerBookingsPageResult> listMyBookings({
    int page = 1,
    int limit = 20,
  }) async {
    return _result;
  }
}

class _LandingRouteProbe extends StatelessWidget {
  const _LandingRouteProbe();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('landing-home'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  GuestBookingLookupResult sampleBooking({
    String bookingNumber = 'TX202607010001',
    String status = 'DRIVER_ASSIGNED',
    String? driverName = 'Driver A',
  }) {
    return GuestBookingLookupResult.fromCustomerBookingsApiJson({
      'bookingId': 10,
      'bookingNumber': bookingNumber,
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
      'passengers': {'adults': 2, 'children': 0, 'infants': 0, 'total': 2},
      'luggage': {
        'carriers20Inch': 0,
        'carriers24InchPlus': 0,
        'golfBags': 0,
      },
      'assignedDriver': driverName == null
          ? null
          : {
              'name': driverName,
              'phone': '+66 80 000 0000',
              'vehicle': {
                'typeCode': 'SUV',
                'typeName': 'SUV',
                'plateNumber': '1กข1234',
                'modelName': 'Camry',
                'color': 'Black',
              },
            },
      'capabilities': {
        'notificationsAvailable': true,
        'trackingAvailable': true,
      },
      'guestAccess': {'token': null, 'expiresAt': null},
    });
  }

  testWidgets('my bookings page renders multiple bookings from mock API', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: MyBookingsPage(
          apiService: _FakeCustomerBookingsApiService(
            CustomerBookingsPageResult(
              bookings: [
                sampleBooking(bookingNumber: 'TX202607010001'),
                sampleBooking(
                  bookingNumber: 'TX202607010002',
                  status: 'OPEN',
                  driverName: null,
                ),
              ],
              total: 2,
              page: 1,
              limit: 20,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내 예약'), findsOneWidget);
    expect(find.text('TX202607010001'), findsOneWidget);
    expect(find.text('TX202607010002'), findsOneWidget);
    expect(find.text('Airport Pickup'), findsNWidgets(2));
    expect(find.textContaining('기사: Driver A'), findsOneWidget);
  });

  testWidgets('my bookings page shows empty state', (tester) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: MyBookingsPage(
          apiService: _FakeCustomerBookingsApiService(
            const CustomerBookingsPageResult(
              bookings: [],
              total: 0,
              page: 1,
              limit: 20,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('연결된 예약이 없습니다. 예약 후 로그인하면 여기에서 확인할 수 있습니다.'), findsOneWidget);
  });

  testWidgets('tapping a booking opens guest lookup detail with initial result', (
    tester,
  ) async {
    final booking = sampleBooking();
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: MyBookingsPage(
          apiService: _FakeCustomerBookingsApiService(
            CustomerBookingsPageResult(
              bookings: [booking],
              total: 1,
              page: 1,
              limit: 20,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('TX202607010001'));
    await tester.pumpAndSettle();

    expect(find.byType(GuestBookingLookupPage), findsOneWidget);
    expect(find.text('TX202607010001'), findsWidgets);
  });

  testWidgets('connected card shows view my bookings button and navigates', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/social/google')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'accessToken': 'access-token',
                'refreshToken': 'refresh-token',
                'expiresIn': 3600,
                'user': {
                  'id': 42,
                  'email': 'guest@example.com',
                  'role': 'CUSTOMER',
                  'name': 'Minji',
                  'phone': null,
                  'locale': 'ko',
                  'isActive': true,
                },
              },
            }),
            200,
          );
        }
        return http.Response('{}', 500);
      }),
    );

    await authController.completeSignInWithIdTokenForTest('mock-google-id-token');

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [
            Locale('en'),
            Locale('ko'),
            Locale('th'),
            Locale('ja'),
            Locale('zh'),
          ],
          localizationsDelegates: [
            AppLocalizationsDelegate('ko'),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: {
            '/my-bookings': (_) => MyBookingsPage(
              apiService: _FakeCustomerBookingsApiService(
                CustomerBookingsPageResult(
                  bookings: [sampleBooking()],
                  total: 1,
                  page: 1,
                  limit: 20,
                ),
              ),
            ),
          },
          home: BookingSocialLoginSection(
            authController: authController,
            claimContext: SocialLoginReturnContext.fromBookingComplete(
              result: BookingCreateResult(
                bookingNumber: 'TX202607010001',
                status: 'PENDING',
                paymentMethod: 'PAY_DRIVER',
                paymentStatus: 'UNPAID',
                totalAmount: 1500,
                currency: 'THB',
                guestAccessToken: 'guest-token',
                boardingQrToken: 'boarding-token',
                trustMessage: 'Booking received',
              ),
              serviceLabel: 'Airport Pickup',
              baseUri: Uri.parse('https://trider.taxi/booking'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내 예약 보기'), findsOneWidget);
    await tester.tap(find.text('내 예약 보기'));
    await tester.pumpAndSettle();

    expect(find.text('내 예약'), findsOneWidget);
  });

  testWidgets('booking complete home button navigates to landing route', (
    tester,
  ) async {
    final authController = await prepareSignedOutAuthController();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [
            Locale('en'),
            Locale('ko'),
            Locale('th'),
            Locale('ja'),
            Locale('zh'),
          ],
          localizationsDelegates: [
            AppLocalizationsDelegate('en'),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          initialRoute: '/booking',
          routes: {
            '/': (_) => const _LandingRouteProbe(),
            '/booking': (_) => BookingCompletePage(
              authController: authController,
              result: BookingCreateResult(
                bookingNumber: 'TX202607010001',
                status: 'PENDING',
                paymentMethod: 'PAY_DRIVER',
                paymentStatus: 'UNPAID',
                totalAmount: 1500,
                currency: 'THB',
                guestAccessToken: 'guest-token',
                boardingQrToken: 'boarding-token',
                trustMessage: 'Booking received',
              ),
              serviceLabel: 'Airport Pickup',
              origin: testBookingLocation(name: 'BKK Airport'),
              destination: testBookingLocation(name: 'Pattaya'),
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BookingCompletePage), findsOneWidget);

    final homeButton = find.widgetWithIcon(ElevatedButton, Icons.home_outlined);
    await tester.ensureVisible(homeButton);
    await tester.tap(homeButton);
    await tester.pumpAndSettle();

    expect(find.text('landing-home'), findsOneWidget);
    expect(find.byType(BookingCompletePage), findsNothing);
  });

  test('customer bookings api parses list response', () async {
    SharedPreferences.setMockInitialValues({
      AuthTokenStorage.accessTokenKey: 'access-token',
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

    final storage = AuthTokenStorage();
    await storage.saveSession(
      const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUser(
          id: 42,
          email: 'guest@example.com',
          role: 'CUSTOMER',
          name: 'Minji',
          phone: null,
          locale: 'ko',
          isActive: true,
        ),
      ),
    );

    final service = CustomerBookingsApiService(
      session: CustomerSession(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/customer/bookings');
          expect(request.headers['Authorization'], 'Bearer access-token');
          return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookings': [
                {
                  'bookingNumber': 'TX202607010001',
                  'status': 'OPEN',
                  'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
                  'serviceType': {'code': 'AIRPORT_PICKUP', 'name': 'Airport Pickup'},
                  'route': {
                    'origin': {'address': 'BKK Airport'},
                    'destination': {'address': 'Pattaya Hotel'},
                  },
                  'pricing': {
                    'totalAmount': 1500,
                    'currency': 'THB',
                    'paymentMethod': 'PAY_DRIVER',
                  },
                  'vehicle': {'typeCode': 'SUV', 'typeName': 'SUV', 'count': 1},
                  'capabilities': {'notificationsAvailable': true},
                  'guestAccess': {'token': null, 'expiresAt': null},
                },
              ],
              'total': 1,
              'page': 1,
              'limit': 20,
            },
          }),
          200,
        );
        }),
        baseUrl: 'http://localhost:3000',
      ),
    );

    final result = await service.listMyBookings();
    expect(result.bookings.length, 1);
    expect(result.bookings.single.bookingNumber, 'TX202607010001');
    expect(result.total, 1);
  });
}
