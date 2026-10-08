import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/flight_lookup_api_service.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/widgets/step_flight_lookup.dart';
import 'package:frontend/features/booking/widgets/step_origin_select.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class _MemoryStorage extends BookingStateStorage {
  _MemoryStorage([this.value]);
  BookingWizardState? value;

  @override
  Future<void> clear() async => value = null;
  @override
  Future<BookingWizardState?> load() async => value;
  @override
  Future<void> save(BookingWizardState state) async => value = state;
}

class _NoopRecentRepository implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption location) async {}

  @override
  Future<List<LocationOption>> load() async => const [];
}

FlightLookupApiService _api({required bool succeeds, bool multiple = false}) {
  return FlightLookupApiService.test(
    baseUrl: 'http://localhost:3000',
    client: MockClient((_) async {
      if (!succeeds) {
        return http.Response(
          jsonEncode({'error_code': 'FLIGHT_NOT_FOUND', 'message': 'none'}),
          404,
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'flightNumber': 'TG401',
            'airlineName': 'Thai Airways',
            'departure': {
              'airportCode': 'ICN',
              'scheduledAt': '2026-10-15T14:00:00Z',
              'scheduledLocal': '2026-10-15T23:00:00+09:00',
            },
            'arrival': {
              'airportCode': 'BKK',
              'scheduledAt': '2026-10-15T19:30:00Z',
            },
            'status': 'SCHEDULED',
            if (multiple)
              'matches': [
                {
                  'flightNumber': 'TG401',
                  'airlineName': 'Thai Airways',
                  'departure': {
                    'airportCode': 'ICN',
                    'scheduledAt': '2026-10-15T14:00:00Z',
                    'scheduledLocal': '2026-10-15T23:00:00+09:00',
                  },
                  'arrival': {
                    'airportCode': 'BKK',
                    'scheduledAt': '2026-10-15T19:30:00Z',
                  },
                },
                {
                  'flightNumber': 'TG401',
                  'airlineName': 'Thai Airways',
                  'departure': {
                    'airportCode': 'PUS',
                    'scheduledAt': '2026-10-15T15:00:00Z',
                    'scheduledLocal': '2026-10-16T00:00:00+09:00',
                  },
                  'arrival': {
                    'airportCode': 'BKK',
                    'scheduledAt': '2026-10-15T20:30:00Z',
                  },
                },
              ],
          },
        }),
        200,
      );
    }),
  );
}

Future<BookingWizardController> _controller() async {
  final controller = BookingWizardController(
    storage: _MemoryStorage(),
    recentLocationsStorage: RecentLocationsStorage(
      guestRepository: _NoopRecentRepository(),
    ),
    now: () => DateTime.parse('2026-10-15T09:00:00+09:00'),
  );
  await controller.initialize(
    initialServiceType: BookingServiceType.airportPickup,
  );
  await controller.updateCustomerInfo(
    flightNumber: 'TG401',
    flightDate: '2026-10-15',
  );
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  BookingWizardController controller,
  FlightLookupApiService api,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => LocaleState()..setLanguage('ko'),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, __) => StepFlightLookup(
                state: controller.state,
                controller: controller,
                flightLookupApi: api,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('flight confirmation applies Bangkok arrival plus 50 minutes', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, _api(succeeds: true));

    await tester.tap(find.byKey(const Key('route_flight_lookup_button')));
    await tester.pumpAndSettle();
    expect(find.text('ICN 23:00 → BKK 02:30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('route_flight_confirm_button_0')));
    await tester.pumpAndSettle();

    expect(controller.state.origin?.code, 'BKK');
    expect(controller.state.pickupDate, '2026-10-16');
    expect(controller.state.pickupTime, '03:20');
    expect(controller.state.flightNumber, 'TG401');
  });

  testWidgets(
    'flight confirmation immediately replaces origin editor with BKK card',
    (tester) async {
      final controller = await _controller();
      final api = _api(succeeds: true);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState()..setLanguage('ko'),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => Column(
                    children: [
                      StepFlightLookup(
                        state: controller.state,
                        controller: controller,
                        flightLookupApi: api,
                      ),
                      StepOriginSelect(
                        embedded: true,
                        serviceType: controller.state.serviceType,
                        selected: controller.state.origin,
                        languageCode: 'ko',
                        onSelected: controller.setOrigin,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('BKK'), findsOneWidget);
      await tester.tap(find.byKey(const Key('route_flight_lookup_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('route_flight_confirm_button_0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
      expect(find.text('BKK'), findsNothing);
    },
  );

  testWidgets('lookup failure offers manual airport and time selection', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, _api(succeeds: false));

    await tester.tap(find.byKey(const Key('route_flight_lookup_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('We could not find the flight'), findsOneWidget);
  });

  testWidgets('multiple flight matches render as separate selectable cards', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, _api(succeeds: true, multiple: true));

    await tester.tap(find.byKey(const Key('route_flight_lookup_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route_flight_result_0')), findsOneWidget);
    expect(find.byKey(const Key('route_flight_result_1')), findsOneWidget);
    expect(
      find.byKey(const Key('route_flight_confirm_button_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('route_flight_confirm_button_1')),
      findsOneWidget,
    );
  });
}
