import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_flight/pages/admin_flight_monitor_page.dart';
import 'package:frontend/features/admin_flight/services/admin_flight_api_service.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';

class _FakeFlightApi extends AdminFlightApiService {
  _FakeFlightApi({
    this.token = 'token',
    this.listResponse,
    this.listError,
    this.syncResponse,
    this.syncError,
  });

  final String? token;
  Map<String, dynamic>? listResponse;
  Object? listError;
  Map<String, dynamic>? syncResponse;
  Object? syncError;
  int listCalls = 0;
  int syncCalls = 0;
  String? lastFlightNumber;
  bool? lastDelayedOnly;

  @override
  Future<String?> getSavedToken() async => token;

  @override
  Future<Map<String, dynamic>> listFlights({
    String? date,
    String? flightNumber,
    String? status,
    bool delayedOnly = false,
    String? bookingNumber,
    int page = 1,
    int pageSize = 20,
  }) async {
    listCalls += 1;
    lastFlightNumber = flightNumber;
    lastDelayedOnly = delayedOnly;
    if (listError != null) throw listError!;
    return listResponse ??
        {
          'page': 1,
          'total': 1,
          'items': [
            {
              'bookingId': 42,
              'bookingNumber': 'TX202607010001',
              'flightNumber': 'TG409',
              'departureAirportIata': 'SIN',
              'arrivalAirportIata': 'BKK',
              'scheduledPickupAt': '2026-07-01 09:30:00',
              'scheduledArrivalAt': '2026-07-01 12:00:00',
              'estimatedArrivalAt': '2026-07-01 12:15:00',
              'actualArrivalAt': null,
              'delayMinutes': 15,
              'flightStatus': 'DELAYED',
              'syncStatus': 'NEVER',
              'lastSyncedAt': null,
            },
          ],
        };
  }

  @override
  Future<Map<String, dynamic>> syncFlight(int bookingId) async {
    syncCalls += 1;
    if (syncError != null) throw syncError!;
    return syncResponse ??
        {
          'bookingId': bookingId,
          'bookingNumber': 'TX202607010001',
          'flightNumber': 'TG409',
          'syncStatus': 'SUCCESS',
          'lastSyncedAt': '2026-07-01 10:00:00',
        };
  }
}

class _FakeDispatchApi extends AdminDispatchApiService {
  @override
  Future<String?> getSavedToken() async => 'token';
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('shows loading then success list', (tester) async {
    final api = _FakeFlightApi();
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('TX202607010001'), findsOneWidget);
    expect(find.textContaining('TG409'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    final api = _FakeFlightApi(listResponse: {'page': 1, 'total': 0, 'items': []});
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    expect(find.text('No airport pickup flights found'), findsOneWidget);
  });

  testWidgets('shows error and retry', (tester) async {
    final api = _FakeFlightApi(listError: const AdminFlightApiException('Boom'));
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    expect(find.text('Boom'), findsOneWidget);
    api.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TX202607010001'), findsOneWidget);
  });

  testWidgets('delayed only filter reloads list', (tester) async {
    final api = _FakeFlightApi();
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delayed only'));
    await tester.pumpAndSettle();
    expect(api.lastDelayedOnly, true);
    expect(api.listCalls, greaterThan(1));
  });

  testWidgets('manual sync updates row', (tester) async {
    final api = _FakeFlightApi();
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pumpAndSettle();
    expect(api.syncCalls, 1);
    expect(find.textContaining('Sync: SUCCESS'), findsOneWidget);
  });

  testWidgets('provider not configured shows snackbar', (tester) async {
    final api = _FakeFlightApi(
      syncResponse: {
        'bookingId': 42,
        'bookingNumber': 'TX202607010001',
        'flightNumber': 'TG409',
        'syncStatus': 'NOT_CONFIGURED',
        'syncError': 'CONFIG_MISSING',
      },
    );
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pumpAndSettle();
    expect(find.text('Flight provider is not configured'), findsOneWidget);
  });
}
