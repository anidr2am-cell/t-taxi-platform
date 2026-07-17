import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/driver_location/models/driver_location.dart';
import 'package:frontend/features/driver_location/pages/admin_driver_monitor_page.dart';
import 'package:frontend/features/driver_location/services/driver_location_api_service.dart';
import 'package:frontend/features/driver_location/services/driver_location_socket_service.dart';
import 'package:frontend/features/driver_location/widgets/driver_live_location_control.dart';
import 'package:frontend/features/driver_location/widgets/guest_driver_tracking_section.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'driver location update uses /api/v1/driver/location and bearer token',
    () async {
      SharedPreferences.setMockInitialValues({
        'driver_access_token': 'driver-token',
      });
      Uri? uri;
      Map<String, String>? headers;
      Map<String, dynamic>? body;
      final api = DriverLocationApiService(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          uri = request.url;
          headers = request.headers;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'accepted': true},
            }),
            200,
          );
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
    },
  );

  test('admin snapshot uses filters and admin bearer token', () async {
    SharedPreferences.setMockInitialValues({
      'admin_access_token': 'admin-token',
    });
    Uri? uri;
    final api = DriverLocationApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        uri = request.url;
        expect(request.headers['Authorization'], 'Bearer admin-token');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [
                {
                  'driverId': 7,
                  'displayName': 'Somchai',
                  'latitude': 12.9,
                  'longitude': 100.8,
                  'stale': false,
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    final items = await api.listAdminLocations(
      onlineOnly: true,
      activeJobOnly: true,
    );

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
        return http.Response(
          jsonEncode({
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
          }),
          200,
        );
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

  testWidgets(
    'driver location waits in assigned status before automatic sharing',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DriverLiveLocationControl(
              hasActiveJob: true,
              bookingNumber: 'TX1',
              bookingStatus: 'DRIVER_ASSIGNED',
            ),
          ),
        ),
      );

      expect(find.textContaining('픽업 장소로 이동'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    },
  );

  testWidgets('driver location auto starts in on-route status', (tester) async {
    final api = _FakeDriverLocationUpdateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(minutes: 5),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(api.calls, 1);
    expect(find.textContaining('위치 공유 중'), findsOneWidget);
  });

  testWidgets('driver location waits for online status before sending', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: null,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(api.calls, 0);
    expect(find.text('Checking driver status'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(api.calls, 1);
  });

  testWidgets('offline transition cancels timers and online resumes tracking', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: false,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(api.calls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.calls, 2);
  });

  testWidgets('first successful send starts one periodic timer', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(api.calls, 2);
  });

  testWidgets('same booking mounted twice keeps one periodic timer', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi();
    Widget controls({bool first = true}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            if (first)
              DriverLiveLocationControl(
                key: const ValueKey('owner'),
                hasActiveJob: true,
                online: true,
                bookingNumber: 'TX1',
                bookingStatus: 'ON_ROUTE',
                api: api,
                positionProvider: () async => _position(),
                interval: const Duration(seconds: 1),
              ),
            DriverLiveLocationControl(
              key: const ValueKey('backup'),
              hasActiveJob: true,
              online: true,
              bookingNumber: 'TX1',
              bookingStatus: 'ON_ROUTE',
              api: api,
              positionProvider: () async => _position(),
              interval: const Duration(seconds: 1),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(controls());
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.calls, 2);

    await tester.pumpWidget(controls(first: false));
    await tester.pump();
    await tester.pump();
    expect(api.calls, 3);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.calls, 4);
  });

  testWidgets('first send failure does not start periodic timer', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi(
      errors: [const DriverLocationApiException('temporary', statusCode: 503)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(api.calls, 1);
  });

  testWidgets('temporary error retries once and then starts periodic timer', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi(
      errors: [const DriverLocationApiException('temporary', statusCode: 503)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 10),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(api.calls, 2);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(api.calls, 3);
  });

  testWidgets('permission denied disables sharing and cancels timers', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi(
      errors: [
        const DriverLocationApiException(
          'Location permission denied',
          errorCode: 'LOCATION_PERMISSION_DENIED',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
            interval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(api.calls, 1);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('booking change invalidates pending retry callback', (
    tester,
  ) async {
    final api = _FakeDriverLocationUpdateApi(
      errors: [const DriverLocationApiException('temporary', statusCode: 503)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: true,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: false,
            bookingNumber: 'TX2',
            bookingStatus: 'ON_ROUTE',
            api: api,
            positionProvider: () async => _position(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(api.calls, 1);
  });

  testWidgets('driver location control prompts when offline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriverLiveLocationControl(
            hasActiveJob: true,
            online: false,
            bookingNumber: 'TX1',
            bookingStatus: 'ON_ROUTE',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      find.text('온라인 전환 후 위치를 공유하세요.\n(กรุณาออนไลน์ก่อนแชร์ตำแหน่ง)'),
      findsOneWidget,
    );
  });

  testWidgets('driver location control hides when there is no active job', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DriverLiveLocationControl(hasActiveJob: false)),
      ),
    );

    expect(find.textContaining('위치 공유'), findsNothing);
  });

  testWidgets('admin monitor shows loading, empty, and error states', (
    tester,
  ) async {
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

  testWidgets(
    'admin monitor lists active offline driver without live location',
    (tester) async {
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
    },
  );

  testWidgets('guest tracking waits in assigned status without location load', (
    tester,
  ) async {
    final api = _FakeGuestLocationApi(
      result: const GuestDriverLocationResult(available: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'DRIVER_ASSIGNED',
            api: api,
            socket: _FakeLocationSocket(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.calls, 0);
    expect(find.text('Driver location'), findsOneWidget);
    expect(find.textContaining('driver has been assigned'), findsOneWidget);
  });

  testWidgets('guest tracking starts after assigned booking becomes on route', (
    tester,
  ) async {
    final api = _FakeGuestLocationApi(
      result: GuestDriverLocationResult(
        available: true,
        bookingNumber: 'TX202607010001',
        bookingStatus: 'ON_ROUTE',
        driver: _guestDriver(recordedAt: DateTime.now().toIso8601String()),
      ),
    );
    final socket = _FakeLocationSocket();
    final lookup = _FakeGuestBookingLookupService([
      _guestLookup(status: 'ON_ROUTE', trackingAvailable: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'DRIVER_ASSIGNED',
            bookingNumber: 'TX202607010001',
            customerPhone: '+66 81 234 5678',
            lookupService: lookup,
            api: api,
            socket: socket,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(api.calls, 0);
    expect(socket.subscribedBookingId, isNull);
    expect(lookup.calls, 0);

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(lookup.calls, 1);
    expect(api.calls, 1);
    expect(socket.connectedGuestToken, 'guest-token-refreshed-1');
    expect(socket.subscribedBookingId, 99);
    expect(find.text('Driver location sharing'), findsOneWidget);
    expect(find.text('Somchai'), findsOneWidget);
  });

  testWidgets('guest tracking cleans up when status polling reaches terminal', (
    tester,
  ) async {
    final socket = _FakeLocationSocket();
    final lookup = _FakeGuestBookingLookupService([
      _guestLookup(status: 'SETTLEMENT_PENDING', trackingAvailable: false),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'PICKED_UP',
            bookingNumber: 'TX202607010001',
            customerPhone: '+66 81 234 5678',
            lookupService: lookup,
            api: _FakeGuestLocationApi(
              result: GuestDriverLocationResult(
                available: true,
                driver: _guestDriver(
                  recordedAt: DateTime.now().toIso8601String(),
                ),
              ),
            ),
            socket: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Somchai'), findsOneWidget);
    expect(socket.subscribedBookingId, 99);

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(lookup.calls, 1);
    expect(socket.disconnectCalls, greaterThanOrEqualTo(1));
    expect(find.text('Driver location'), findsNothing);
    expect(find.text('Somchai'), findsNothing);
  });

  testWidgets('guest tracking shows initial live location on route', (
    tester,
  ) async {
    final api = _FakeGuestLocationApi(
      result: GuestDriverLocationResult(
        available: true,
        bookingNumber: 'TX202607010001',
        bookingStatus: 'ON_ROUTE',
        driver: _guestDriver(recordedAt: DateTime.now().toIso8601String()),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'ON_ROUTE',
            api: api,
            socket: _FakeLocationSocket(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(find.text('Driver location sharing'), findsOneWidget);
    expect(find.text('Somchai'), findsOneWidget);
    expect(find.text('Open in map'), findsOneWidget);
  });

  testWidgets('guest tracking ignores older and other booking socket events', (
    tester,
  ) async {
    final socket = _FakeLocationSocket();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverTrackingSection(
            bookingId: 99,
            guestAccessToken: 'guest-token',
            bookingStatus: 'ON_ROUTE',
            api: _FakeGuestLocationApi(
              result: GuestDriverLocationResult(
                available: true,
                driver: _guestDriver(
                  name: 'Fresh Driver',
                  recordedAt: '2026-07-01T10:00:00.000Z',
                ),
              ),
            ),
            socket: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.emitGuest({
      'bookingId': 100,
      'available': true,
      'driver': {
        'displayName': 'Other Booking',
        'latitude': 13,
        'longitude': 100,
        'recordedAt': '2026-07-01T10:05:00.000Z',
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('Fresh Driver'), findsOneWidget);
    expect(find.text('Other Booking'), findsNothing);

    socket.emitGuest({
      'bookingId': 99,
      'available': true,
      'driver': {
        'displayName': 'Old Driver',
        'latitude': 13,
        'longitude': 100,
        'recordedAt': '2026-07-01T09:59:00.000Z',
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('Fresh Driver'), findsOneWidget);
    expect(find.text('Old Driver'), findsNothing);
  });

  testWidgets('guest tracking terminal states render safely', (tester) async {
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

    expect(find.text('Driver location'), findsNothing);
  });
}

class _FakeLocationSocket extends DriverLocationSocketService {
  String? connectedGuestToken;
  int? subscribedBookingId;
  bool disconnected = false;
  int disconnectCalls = 0;

  @override
  Future<void> connect({String? accessToken, String? guestAccessToken}) async {
    connectedGuestToken = guestAccessToken;
  }

  @override
  void subscribeGuest(int bookingId) {
    subscribedBookingId = bookingId;
  }

  @override
  void subscribeAdmin() {}

  @override
  void disconnect() {
    disconnected = true;
    disconnectCalls += 1;
  }

  void emitGuest(Map<String, dynamic> payload) {
    onGuestChanged?.call(payload);
  }
}

class _FakeGuestBookingLookupService extends GuestBookingLookupService {
  _FakeGuestBookingLookupService(this.results);

  final List<GuestBookingLookupResult> results;
  int calls = 0;

  @override
  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
  }) async {
    calls += 1;
    final index = (calls - 1).clamp(0, results.length - 1).toInt();
    return results[index];
  }
}

class _FakeDispatchDriversApi extends AdminDispatchApiService {
  _FakeDispatchDriversApi({required this.drivers});

  final List<Map<String, dynamic>> drivers;

  @override
  Future<List<dynamic>> listDrivers({bool? archived}) async => drivers;
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
  int calls = 0;

  @override
  Future<GuestDriverLocationResult> getGuestDriverLocation({
    required int bookingId,
    required String guestAccessToken,
  }) async {
    calls += 1;
    return result;
  }
}

DriverLocation _guestDriver({String name = 'Somchai', String? recordedAt}) {
  return DriverLocation(
    driverId: 0,
    displayName: name,
    vehicle: 'SUV / TEST-001',
    latitude: 12.9236,
    longitude: 100.8825,
    recordedAt: recordedAt,
    lastSeenAt: recordedAt,
    stale: false,
  );
}

GuestBookingLookupResult _guestLookup({
  required String status,
  required bool trackingAvailable,
}) {
  return GuestBookingLookupResult(
    bookingId: 99,
    bookingNumber: 'TX202607010001',
    status: status,
    scheduledPickupAt: '2026-07-01T09:30:00+07:00',
    serviceTypeName: 'Airport Pickup',
    originAddress: 'BKK Airport',
    destinationAddress: 'Pattaya Hotel',
    totalAmount: 1500,
    currency: 'THB',
    paymentMethod: 'PAY_DRIVER',
    guestAccessToken: 'guest-token-refreshed-1',
    guestAccessExpiresAt: '2026-07-02T00:00:00Z',
    capabilities: GuestBookingCapabilities(
      chatAvailable: true,
      notificationsAvailable: true,
      dropoffQrIssueAvailable: status == 'PICKED_UP',
      reviewAvailable: false,
      trackingAvailable: trackingAvailable,
      boardingQrRecoverable: false,
      boardingQrPreviouslyIssued: false,
    ),
    customerPhone: '+66 81 234 5678',
  );
}

Position _position() => Position(
  latitude: 12.9236,
  longitude: 100.8825,
  timestamp: DateTime.now(),
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 0,
  speed: 10,
  speedAccuracy: 0,
);

class _FakeDriverLocationUpdateApi extends DriverLocationApiService {
  _FakeDriverLocationUpdateApi({List<DriverLocationApiException>? errors})
    : errors = List.of(errors ?? const []);

  final List<DriverLocationApiException> errors;
  int calls = 0;

  @override
  Future<void> updateDriverLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? heading,
    double? speedKph,
    DateTime? recordedAt,
  }) async {
    calls += 1;
    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
  }
}
