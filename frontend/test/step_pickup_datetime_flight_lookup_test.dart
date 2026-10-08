import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/flight_lookup_api_service.dart';
import 'package:frontend/features/booking/widgets/step_flight_lookup.dart';
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

FlightLookupApiService _api({required bool succeeds}) {
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
            },
            'arrival': {
              'airportCode': 'BKK',
              'scheduledAt': '2026-10-15T19:30:00Z',
            },
            'status': 'SCHEDULED',
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
    expect(find.text('ICN → BKK'), findsOneWidget);

    await tester.tap(find.byKey(const Key('route_flight_confirm_button')));
    await tester.pumpAndSettle();

    expect(controller.state.origin?.code, 'BKK');
    expect(controller.state.pickupDate, '2026-10-16');
    expect(controller.state.pickupTime, '03:20');
    expect(controller.state.flightNumber, 'TG401');
  });

  testWidgets('lookup failure offers manual airport and time selection', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, _api(succeeds: false));

    await tester.tap(find.byKey(const Key('route_flight_lookup_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('We could not find the flight'), findsOneWidget);
  });
}
