import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/services/mileage_api_service.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/customer_session.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/pages/my_bookings_page.dart';
import 'package:frontend/features/booking/services/customer_bookings_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerSession.resetSharedForTesting();
  });

  Future<AuthController> seedLoggedInController({
    required http.Client client,
    AuthTokenStorage? storage,
  }) async {
    final tokenStorage = storage ?? AuthTokenStorage();
    await tokenStorage.saveSession(
      const AuthSession(
        accessToken: 'expired',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 42, role: 'CUSTOMER', email: 'line@example.com'),
      ),
    );
    final session = CustomerSession(
      tokenStorage: tokenStorage,
      httpClient: client,
      baseUrl: 'http://localhost:3000',
    );
    final controller = AuthController(
      tokenStorage: tokenStorage,
      customerSession: session,
    );
    await controller.initialize();
    return controller;
  }

  testWidgets('my bookings refreshes expired token and loads list', (
    tester,
  ) async {
    var refreshCalls = 0;
    var bookingsCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'accessToken': 'fresh-token', 'expiresIn': 3600},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/customer/bookings')) {
        bookingsCalls++;
        final auth = request.headers['authorization'];
        if (auth == 'Bearer expired') {
          return http.Response(
            jsonEncode({
              'success': false,
              'error_code': 'UNAUTHORIZED',
              'message': 'Invalid or expired token',
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookings': [
                {
                  'bookingNumber': 'TX202608310005',
                  'status': 'OPEN',
                  'scheduledPickupAt': '2026-08-31T09:30:00+07:00',
                  'serviceType': {
                    'code': 'CITY_TRANSFER',
                    'name': 'City Transfer',
                  },
                  'route': {
                    'origin': {'address': 'Bangkok'},
                    'destination': {'address': 'Pattaya'},
                  },
                  'pricing': {
                    'totalAmount': 1300,
                    'currency': 'THB',
                    'paymentMethod': 'PAY_DRIVER',
                  },
                  'vehicle': {'typeCode': 'SEDAN', 'typeName': 'Sedan', 'count': 1},
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
      }
      return http.Response('{}', 500);
    });

    final tokenStorage = AuthTokenStorage();
    final customerSession = CustomerSession(
      tokenStorage: tokenStorage,
      httpClient: client,
      baseUrl: 'http://localhost:3000',
    );
    final authController = await seedLoggedInController(
      client: client,
      storage: tokenStorage,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(
          controller: authController,
          child: MyBookingsPage(
            apiService: CustomerBookingsApiService(session: customerSession),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(bookingsCalls, 2);
    expect(find.text('TX202608310005'), findsOneWidget);
    expect(authController.isLoggedIn, isTrue);
    expect(
      (await tokenStorage.readAccessToken()),
      'fresh-token',
    );
  });

  testWidgets('my bookings signs out when refresh fails', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        return http.Response(
          jsonEncode({
            'success': false,
            'error_code': 'AUTH_INVALID',
            'message': 'Invalid refresh token',
          }),
          401,
        );
      }
      return http.Response(
        jsonEncode({
          'success': false,
          'error_code': 'UNAUTHORIZED',
          'message': 'Invalid or expired token',
        }),
        401,
      );
    });

    final tokenStorage = AuthTokenStorage();
    final customerSession = CustomerSession(
      tokenStorage: tokenStorage,
      httpClient: client,
      baseUrl: 'http://localhost:3000',
    );
    final authController = await seedLoggedInController(
      client: client,
      storage: tokenStorage,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(
          controller: authController,
          child: MyBookingsPage(
            apiService: CustomerBookingsApiService(session: customerSession),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(authController.isLoggedIn, isFalse);
    expect(await tokenStorage.loadSession(), isNull);
  });

  test('mileage service refreshes expired token before loading balance', () async {
    var refreshCalls = 0;
    final tokenStorage = AuthTokenStorage();
    await tokenStorage.saveSession(
      const AuthSession(
        accessToken: 'expired',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 1, role: 'CUSTOMER', email: 'user@example.com'),
      ),
    );

    final service = MileageApiService(
      session: CustomerSession(
        tokenStorage: tokenStorage,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls++;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'accessToken': 'fresh-token', 'expiresIn': 3600},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/customer/mileage')) {
            final auth = request.headers['authorization'];
            if (auth == 'Bearer expired') {
              return http.Response(
                jsonEncode({
                  'success': false,
                  'error_code': 'UNAUTHORIZED',
                  'message': 'Invalid or expired token',
                }),
                401,
              );
            }
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'balance': 900},
              }),
              200,
            );
          }
          return http.Response('{}', 500);
        }),
        baseUrl: 'http://localhost:3000',
      ),
    );

    final result = await service.getMileageBalance();
    expect(result.balance, 900);
    expect(refreshCalls, 1);
    expect(await tokenStorage.readAccessToken(), 'fresh-token');
  });

  test('getMileageBalance rejects access-only storage without refresh token', () async {
    final tokenStorage = AuthTokenStorage();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AuthTokenStorage.accessTokenKey, 'access-only');
    await prefs.setString(
      AuthTokenStorage.userJsonKey,
      jsonEncode(
        const AuthUser(id: 1, role: 'CUSTOMER', email: 'user@example.com').toJson(),
      ),
    );

    final service = MileageApiService(
      session: CustomerSession(
        tokenStorage: tokenStorage,
        httpClient: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
    );

    expect(
      () => service.getMileageBalance(),
      throwsA(
        isA<MileageApiException>().having(
          (error) => error.message,
          'message',
          'Authentication required',
        ),
      ),
    );
  });
}
