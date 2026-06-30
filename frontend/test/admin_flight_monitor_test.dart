import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_flight/pages/admin_flight_monitor_page.dart';
import 'package:frontend/features/admin_flight/services/admin_flight_api_service.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';

class _FakeFlightApi extends AdminFlightApiService {
  _FakeFlightApi({
    this.listResponse,
    this.listError,
    this.syncResponse,
    this.statusResponse,
  });

  Map<String, dynamic>? listResponse;
  Object? listError;
  Map<String, dynamic>? syncResponse;
  Object? syncError;
  Map<String, dynamic>? statusResponse;
  Object? statusError;
  Map<String, dynamic>? runCycleResponse;
  Object? runCycleError;
  int listCalls = 0;
  int syncCalls = 0;
  int statusCalls = 0;
  int runCycleCalls = 0;
  String? lastFlightNumber;
  bool? lastDelayedOnly;

  @override
  Future<String?> getSavedToken() async => 'token';

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

  @override
  Future<Map<String, dynamic>> getSyncStatus() async {
    statusCalls += 1;
    if (statusError != null) throw statusError!;
    return statusResponse ??
        {
          'enabled': false,
          'running': false,
          'providerConfigured': false,
          'intervalMs': 300000,
          'lastCycleStartedAt': null,
          'lastCycleCompletedAt': null,
          'lastCycle': null,
          'nextExpectedRunAt': null,
        };
  }

  @override
  Future<Map<String, dynamic>> runSyncCycle() async {
    runCycleCalls += 1;
    if (runCycleError != null) throw runCycleError!;
    return runCycleResponse ??
        {
          'selected': 1,
          'succeeded': 1,
          'skipped': 0,
          'failed': 0,
          'rateLimited': false,
          'configMissing': false,
          'durationMs': 12,
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

  testWidgets('shows automatic sync disabled and provider missing status', (tester) async {
    final api = _FakeFlightApi();
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Worker: Disabled'), findsOneWidget);
    expect(find.textContaining('Provider: Not configured'), findsOneWidget);
  });

  testWidgets('shows last cycle summary and running indicator', (tester) async {
    final api = _FakeFlightApi(
      statusResponse: {
        'enabled': true,
        'running': true,
        'providerConfigured': true,
        'intervalMs': 300000,
        'lastCycleCompletedAt': '2026-07-01T10:00:00.000Z',
        'lastCycle': {
          'selected': 4,
          'succeeded': 3,
          'failed': 1,
          'skipped': 0,
        },
      },
    );
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Worker: Enabled'), findsOneWidget);
    expect(find.textContaining('Provider: Configured'), findsOneWidget);
    expect(find.textContaining('success 3'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
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

  testWidgets('status refresh reloads worker status', (tester) async {
    final api = _FakeFlightApi();
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(api.statusCalls, greaterThan(1));
  });

  testWidgets('run sync cycle calls API and refreshes list', (tester) async {
    final api = _FakeFlightApi(
      statusResponse: {
        'enabled': true,
        'running': false,
        'providerConfigured': true,
        'intervalMs': 300000,
        'lastCycleCompletedAt': null,
        'lastCycle': null,
      },
    );
    await tester.pumpWidget(_wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run sync cycle'));
    await tester.pumpAndSettle();
    expect(api.runCycleCalls, 1);
    expect(api.listCalls, greaterThan(1));
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

  testWidgets('flight monitor has no horizontal overflow at 768px', (tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeFlightApi();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(768, 1024)),
        child: _wrap(AdminFlightMonitorPage(api: api, dispatchApi: _FakeDispatchApi())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('TX202607010001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
