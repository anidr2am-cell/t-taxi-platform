import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_manual_flight_section.dart';
import 'package:frontend/features/booking/models/flight_lookup_models.dart';
import 'package:frontend/features/booking/services/flight_lookup_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ko'),
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

FlightLookupApiService _flightApi(MockClient client) {
  return FlightLookupApiService.test(
    client: client,
    baseUrl: 'http://mock.test',
  );
}

void main() {
  testWidgets('does not auto-change pickup; shows conflict after confirm', (
    tester,
  ) async {
    DateTime? pickup = DateTime(2026, 9, 24, 10, 0);
    FlightSearchResult? confirmed;

    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'flightNumber': 'TG123',
            'departure': {
              'airportCode': 'ICN',
              'scheduledAt': '2026-09-24T01:00:00.000Z',
            },
            'arrival': {
              'airportCode': 'BKK',
              'scheduledAt': '2026-09-24T05:00:00.000Z',
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _wrap(
        AdminManualFlightSection(
          flightNumber: 'TG123',
          pickupDateIsoOrBangkokDate: '2026-09-24',
          pickupAtBangkok: pickup,
          flightLookupApi: _flightApi(client),
          onFlightNumberChanged: (_) {},
          onConfirmedLookup: (r) => confirmed = r,
          onPickupAtApply: (value) => pickup = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adminFlightSearchButton')));
    await tester.pumpAndSettle();
    expect(pickup, DateTime(2026, 9, 24, 10, 0));

    await tester.tap(find.byKey(const Key('adminFlightLookupConfirm')));
    await tester.pumpAndSettle();
    expect(confirmed, isNotNull);
    expect(find.byKey(const Key('adminFlightPickupConflictWarning')), findsOneWidget);

    await tester.tap(find.byKey(const Key('adminFlightPickupUseFlight')));
    await tester.pumpAndSettle();
    final applied = pickup!;
    expect(applied.hour, 12);
    expect(applied.minute, 0);
  });

  testWidgets('lookup failure still allows manual flight number entry', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'message': 'not found',
          'error_code': 'FLIGHT_NOT_FOUND',
        }),
        404,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _wrap(
        AdminManualFlightSection(
          flightNumber: 'NOTFOUND',
          pickupDateIsoOrBangkokDate: '2026-09-24',
          pickupAtBangkok: DateTime(2026, 9, 24, 10, 0),
          flightLookupApi: _flightApi(client),
          onFlightNumberChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adminFlightSearchButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminFlightLookupError')), findsOneWidget);
    expect(find.byKey(const Key('adminManualFlightNumber')), findsOneWidget);
  });
}
