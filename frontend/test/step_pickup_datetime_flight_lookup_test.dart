import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/flight_lookup_api_service.dart';
import 'package:frontend/features/booking/widgets/step_pickup_datetime.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class _NoopStorage extends BookingStateStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<BookingWizardState?> load() async => null;

  @override
  Future<void> save(BookingWizardState state) async {}
}

Map<String, dynamic> _successPayload() => {
  'success': true,
  'data': {
    'flightNumber': 'TG401',
    'airlineName': 'Thai Airways International',
    'departure': {
      'airportCode': 'BKK',
      'airportName': 'Bangkok Suvarnabhumi',
      'scheduledAt': '2026-07-01T09:30:00Z',
    },
    'arrival': {
      'airportCode': 'BKK',
      'airportName': 'Bangkok Suvarnabhumi',
      'scheduledAt': '2026-07-01T12:45:00Z',
      'estimatedAt': '2026-07-01T13:00:00Z',
    },
    'status': 'SCHEDULED',
    'delayMinutes': 15,
  },
};

FlightLookupApiService _apiForResponses(List<http.Response> responses) {
  var index = 0;
  return FlightLookupApiService.test(
    baseUrl: 'http://localhost:3000',
    client: MockClient((request) async {
      final response = responses[index];
      index += 1;
      return response;
    }),
  );
}

Future<void> _pumpStep(
  WidgetTester tester, {
  required BookingWizardController controller,
  required FlightLookupApiService api,
  BookingServiceType serviceType = BookingServiceType.airportPickup,
  ValueChanged<String>? onFlightNumberChanged,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => LocaleState(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => StepPickupDateTime(
                embedded: true,
                state: controller.state.copyWith(serviceType: serviceType),
                controller: controller,
                flightLookupApi: api,
                onFlightNumberChanged: onFlightNumberChanged ?? (_) {},
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
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime.utc(2026, 7, 1, 2, 0);

  group('StepPickupDateTime flight lookup', () {
    late BookingWizardController controller;

    setUp(() async {
      controller = BookingWizardController(
        storage: _NoopStorage(),
        now: () => fixedNow,
      );
      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
    });

    testWidgets('shows result card after successful lookup', (tester) async {
      final api = _apiForResponses([
        http.Response(jsonEncode(_successPayload()), 200),
      ]);

      await _pumpStep(tester, controller: controller, api: api);
      await tester.enterText(find.byKey(const Key('flight_number_field')), 'TG401');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flight_lookup_search_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thai Airways International'), findsOneWidget);
      expect(find.text('BKK → BKK'), findsOneWidget);
      expect(find.text('This is my flight'), findsOneWidget);
    });

    testWidgets('shows not-found guidance for FLIGHT_NOT_FOUND', (tester) async {
      final api = _apiForResponses([
        http.Response(jsonEncode({
          'success': false,
          'error_code': 'FLIGHT_NOT_FOUND',
          'message': 'Flight not found',
        }), 404),
      ]);

      await _pumpStep(tester, controller: controller, api: api);
      await tester.enterText(find.byKey(const Key('flight_number_field')), 'TG999');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flight_lookup_search_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('No flight was found for that number'),
        findsOneWidget,
      );
    });

    testWidgets('shows reassuring provider-unavailable guidance', (tester) async {
      final api = _apiForResponses([
        http.Response(jsonEncode({
          'success': false,
          'error_code': 'FLIGHT_PROVIDER_NOT_CONFIGURED',
          'message': 'Flight provider is not configured',
        }), 503),
      ]);

      await _pumpStep(tester, controller: controller, api: api);
      await tester.enterText(find.byKey(const Key('flight_number_field')), 'TG401');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flight_lookup_search_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('You can still continue booking'),
        findsOneWidget,
      );
    });

    testWidgets('clears lookup result when flight number changes', (tester) async {
      final api = _apiForResponses([
        http.Response(jsonEncode(_successPayload()), 200),
      ]);

      await _pumpStep(tester, controller: controller, api: api);
      const flightField = Key('flight_number_field');
      await tester.enterText(find.byKey(flightField), 'TG401');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flight_lookup_search_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thai Airways International'), findsOneWidget);

      await tester.enterText(find.byKey(flightField), 'TG402');
      await tester.pump();

      expect(find.text('Thai Airways International'), findsNothing);
    });

    testWidgets('hides flight lookup UI for non-airport-pickup service', (
      tester,
    ) async {
      final api = _apiForResponses([]);

      await _pumpStep(
        tester,
        controller: controller,
        api: api,
        serviceType: BookingServiceType.airportDropoff,
      );

      expect(find.text('Look up'), findsNothing);
      expect(find.text('Flight Number'), findsNothing);
    });
  });

  group('flight lookup does not block wizard step 3', () {
    test('canProceedFromStep(3) without lookup', () async {
      final controller = BookingWizardController(
        storage: _NoopStorage(),
        now: () => fixedNow,
      );
      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
      await controller.updateCustomerInfo(flightNumber: 'TG401');

      expect(controller.canProceedFromStep(3), isTrue);
    });

    test('canProceedFromStep(3) remains true after failed lookup state only', () async {
      final controller = BookingWizardController(
        storage: _NoopStorage(),
        now: () => fixedNow,
      );
      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
      await controller.updateCustomerInfo(flightNumber: 'TG401');

      expect(controller.state.flightNumber, 'TG401');
      expect(controller.canProceedFromStep(3), isTrue);
    });

    test('canProceedFromStep(3) without flight number still depends on pickup time only', () async {
      final controller = BookingWizardController(
        storage: _NoopStorage(),
        now: () => fixedNow,
      );
      await controller.initialize();

      expect(controller.canProceedFromStep(3), isTrue);
      expect(controller.state.flightNumber, isEmpty);
    });
  });

  group('StepPickupDateTime flight pickup time conflict', () {
    late BookingWizardController controller;

    setUp(() async {
      controller = BookingWizardController(
        storage: _NoopStorage(),
        now: () => fixedNow,
      );
      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
    });

    Future<void> lookupAndConfirm(WidgetTester tester) async {
      final api = _apiForResponses([
        http.Response(jsonEncode(_successPayload()), 200),
      ]);
      await _pumpStep(tester, controller: controller, api: api);
      await tester.enterText(find.byKey(const Key('flight_number_field')), 'TG401');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flight_lookup_search_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('flight_lookup_confirm_button')));
      await tester.pump();
    }

    testWidgets('shows conflict UI when pickup differs by 30+ minutes', (
      tester,
    ) async {
      await lookupAndConfirm(tester);

      expect(find.byKey(const Key('flight_pickup_conflict_warning')), findsOneWidget);
      expect(
        find.textContaining('differ by 525 minutes'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('flight_pickup_use_manual_tile')), findsOneWidget);
      expect(find.byKey(const Key('flight_pickup_use_flight_tile')), findsOneWidget);
    });

    testWidgets('hides conflict UI when pickup differs by less than 30 minutes', (
      tester,
    ) async {
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 19, 20));
      await lookupAndConfirm(tester);

      expect(find.byKey(const Key('flight_pickup_conflict_warning')), findsNothing);
      expect(find.byKey(const Key('flight_pickup_use_manual_tile')), findsNothing);
    });

    testWidgets('uses flight arrival time when flight option is selected', (
      tester,
    ) async {
      await lookupAndConfirm(tester);

      final flightTile = find.byKey(const Key('flight_pickup_use_flight_tile'));
      await tester.ensureVisible(flightTile);
      await tester.tap(flightTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.state.pickupDate, '2026-07-01');
      expect(controller.state.pickupTime, '19:45');
      expect(controller.scheduledPickupAtIso(), '2026-07-01T19:45:00+07:00');
      expect(find.byKey(const Key('flight_pickup_conflict_warning')), findsNothing);
    });

    testWidgets('keeps manual pickup when manual option is selected', (
      tester,
    ) async {
      await lookupAndConfirm(tester);

      final manualTile = find.byKey(const Key('flight_pickup_use_manual_tile'));
      await tester.ensureVisible(manualTile);
      await tester.tap(manualTile);
      await tester.pump();

      expect(controller.state.pickupDate, '2026-07-01');
      expect(controller.state.pickupTime, '11:00');
      expect(controller.scheduledPickupAtIso(), '2026-07-01T11:00:00+07:00');
      expect(find.byKey(const Key('flight_pickup_final_summary')), findsOneWidget);
    });

    testWidgets('clears conflict UI after pickup time is edited manually', (
      tester,
    ) async {
      await lookupAndConfirm(tester);
      expect(find.byKey(const Key('flight_pickup_conflict_warning')), findsOneWidget);

      await controller.setPickupDateTime(DateTime(2026, 7, 1, 19, 20));
      await tester.pump();

      expect(find.byKey(const Key('flight_pickup_conflict_warning')), findsNothing);
    });
  });
}
