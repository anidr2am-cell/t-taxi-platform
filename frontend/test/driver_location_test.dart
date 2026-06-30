import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/driver_location/models/driver_location.dart';
import 'package:frontend/features/driver_location/pages/admin_driver_monitor_page.dart';
import 'package:frontend/features/driver_location/services/driver_location_api_service.dart';
import 'package:frontend/features/driver_location/services/driver_location_socket_service.dart';
import 'package:frontend/features/driver_location/widgets/driver_live_location_control.dart';
import 'package:frontend/features/driver_location/widgets/guest_driver_tracking_section.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('driver location update uses /api/v1/driver/location and bearer token', () async {
    SharedPreferences.setMockInitialValues({'driver_access_token': 'driver-token'});
    Uri? uri;
    Map<String, String>? headers;
    Map<String, dynamic>? body;
    final api = DriverLocationApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        uri = request.url;
        headers = request.headers;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'success': true, 'data': {'accepted': true}}), 200);
      }),
    );

    await api.updateDriverLocation(
      latitude: 12.9236,
      longitude: 100.8825,
      accuracyMeters: 15,
      heading: 120,
      speedKph: 35,
      recordedAt: DateTime.parse('2026-07-01T10:30:00+07:00'),
    );

    expect(uri!.path, '/api/v1/driver/location');
    expect(headers!['Authorization'], 'Bearer driver-token');
    expect(body!['latitude'], 12.9236);
    expect(body!['longitude'], 100.8825);
  });

  test('admin snapshot uses filters and admin bearer token', () async {
    SharedPreferences.setMockInitialValues({'admin_access_token': 'admin-token'});
    Uri? uri;
    final api = DriverLocationApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        uri = request.url;
        expect(request.headers['Authorization'], 'Bearer admin-token');
        return http.Response(jsonEncode({
          'success': true,
          'data': {
            'items': [
              {
                'driverId': 7,
                'displayName': 'Somchai',
                'latitude': 12.9,
                'longitude': 100.8,
                'stale': false,
              }
            ],
          },
        }), 200);
      }),
    );

    final items = await api.listAdminLocations(onlineOnly: true, activeJobOnly: true);

    expect(uri!.path, '/api/v1/admin/drivers/locations');
    expect(uri!.queryParameters['onlineOnly'], 'true');
    expect(uri!.queryParameters['activeJobOnly'], 'true');
    expect(items.single.displayName, 'Somchai');
  });

  test('guest location uses header token and no query token', () async {
    Uri? uri;
    Map<String, String>? headers;
    final api = DriverLocationApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        uri = request.url;
        headers = request.headers;
        return http.Response(jsonEncode({
          'success': true,
          'data': {
            'available': true,
            'driver': {
              'driverId': 7,
              'displayName': 'Somchai',
              'latitude': 12.9,
              'longitude': 100.8,
              'stale': false,
            },
          },
        }), 200);
      }),
    );

    final result = await api.getGuestDriverLocation(
      bookingId: 99,
      guestAccessToken: 'guest-token',
    );

    expect(uri!.path, '/api/v1/public/bookings/99/driver-location');
    expect(uri!.queryParameters.containsKey('guestAccessToken'), false);
    expect(headers!['X-Guest-Access-Token'], 'guest-token');
    expect(result.available, true);
  });

  testWidgets('driver location permission is not requested before enabling sharing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(hasActiveJob: true),
        ),
      ),
    );

    expect(find.text('Share live location'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('driver location control prompts when offline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(hasActiveJob: true, online: false),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Go online before sharing live location.'), findsOneWidget);
  });

  testWidgets('driver location control hides when there is no active job', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(hasActiveJob: false),
        ),
      ),
    );

    expect(find.text('Share live location'), findsNothing);
  });

  testWidgets('admin monitor shows loading, empty, and error states', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDriverMonitorPage(
            key: const ValueKey('admin-monitor-empty'),
            api: _FakeAdminLocationApi(items: const []),
            dispatchApi: _FakeDispatchDriversApi(drivers: const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drivers'), findsOneWidget);
    expect(find.text('No drivers match the current filters'), findsOneWidget);
    expect(find.text('No live driver locations on the map'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDriverMonitorPage(
            key: const ValueKey('admin-monitor-error'),
            api: _FakeAdminLocationApi(error: 'network'),
            dispatchApi: _FakeDispatchDriversApi(drivers: const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('network'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('admin monitor lists active offline driver without live location', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDriverMonitorPage(
            api: _FakeAdminLocationApi(items: const []),
            dispatchApi: _FakeDispatchDriversApi(
              drivers: [
                {
                  'driverId': 1,
                  'displayName': 'Local Driver',
                  'activeState': 'ACTIVE',
                  'onlineState': 'OFFLINE',
                  'activeAssignmentCount': 0,
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local Driver'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('No location'), findsOneWidget);
  });

  testWidgets('guest tracking unavailable and terminal states render safely', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'DRIVER_ASSIGNED',
            api: _FakeGuestLocationApi(
              result: const GuestDriverLocationResult(available: false),
            ),
            socket: _FakeLocationSocket(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Track driver'), findsOneWidget);
    expect(find.text('Driver location is not available yet.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'COMPLETED',
            api: _FakeGuestLocationApi(
              result: const GuestDriverLocationResult(available: false),
            ),
            socket: _FakeLocationSocket(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Track driver'), findsNothing);
  });
}

class _FakeLocationSocket extends DriverLocationSocketService {
  @override
  Future<void> connect({String? accessToken, String? guestAccessToken}) async {}

  @override
  void subscribeGuest(int bookingId) {}

  @override
  void subscribeAdmin() {}

  @override
  void disconnect() {}
}

class _FakeDispatchDriversApi extends AdminDispatchApiService {
  _FakeDispatchDriversApi({required this.drivers});

  final List<Map<String, dynamic>> drivers;

  @override
  Future<List<dynamic>> listDrivers() async => drivers;
}

class _FakeAdminLocationApi extends DriverLocationApiService {
  _FakeAdminLocationApi({this.items = const [], this.error});

  final List<DriverLocation> items;
  final String? error;

  @override
  Future<List<DriverLocation>> listAdminLocations({
    bool onlineOnly = false,
    bool activeJobOnly = false,
    bool staleOnly = false,
  }) async {
    if (error != null) throw DriverLocationApiException(error!);
    return items;
  }
}

class _FakeGuestLocationApi extends DriverLocationApiService {
  _FakeGuestLocationApi({required this.result});

  final GuestDriverLocationResult result;

  @override
  Future<GuestDriverLocationResult> getGuestDriverLocation({
    required int bookingId,
    required String guestAccessToken,
  }) async {
    return result;
  }
}
