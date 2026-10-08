import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/utils/booking_entry_query.dart';
import 'package:frontend/features/booking/utils/flight_time_format.dart';
import 'package:frontend/features/booking/widgets/google_places_search_field.dart';
import 'package:frontend/features/booking/widgets/step_pickup_datetime.dart';
import 'package:frontend/providers/booking_provider.dart';
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
  _NoopRecentRepository([this.items = const []]);
  final List<LocationOption> items;

  @override
  Future<void> add(LocationOption location) async {}
  @override
  Future<List<LocationOption>> load() async => items;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('booking query parser is extensible and parses service safely', () {
    final args = BookingEntryQuery.parse(
      Uri.parse('/booking?service=AIRPORT_PICKUP&from=BKK&to=PATTAYA'),
    );
    expect(args?.serviceType, BookingServiceType.airportPickup);
    expect(args?.origin, isNull);
    expect(args?.destination, isNull);
  });

  test(
    'URL service overrides restored draft and clears airport time',
    () async {
      final controller = BookingWizardController(
        storage: _MemoryStorage(
          const BookingWizardState(
            serviceType: BookingServiceType.cityTransfer,
            pickupDate: '2026-10-20',
            pickupTime: '10:00',
          ),
        ),
        now: () => DateTime.parse('2026-10-08T12:00:00+07:00'),
      );
      await controller.initialize(
        initialServiceType: BookingServiceType.airportPickup,
      );
      expect(controller.state.serviceType, BookingServiceType.airportPickup);
      expect(controller.state.pickupDate, isNull);
      expect(controller.state.pickupTime, isNull);
      expect(
        controller.canProceedFromStep(BookingWizardSteps.schedule),
        isFalse,
      );
    },
  );

  test('expired restored pickup is cleared instead of defaulted', () async {
    final controller = BookingWizardController(
      storage: _MemoryStorage(
        const BookingWizardState(
          serviceType: BookingServiceType.airportPickup,
          pickupDate: '2026-10-07',
          pickupTime: '10:00',
        ),
      ),
      now: () => DateTime.parse('2026-10-08T12:00:00+07:00'),
    );
    await controller.initialize();
    expect(controller.state.pickupDate, isNull);
    expect(controller.state.pickupTime, isNull);
  });

  test('UTC arrival is converted to Bangkok time on a Seoul device', () {
    final seoulNow = DateTime.parse('2026-10-15T23:00:00+09:00');
    expect(seoulNow.timeZoneOffset, isNot(const Duration(hours: 7)));
    expect(
      FlightTimeFormat.bangkokWallClock('2026-10-15T19:30:00Z'),
      DateTime(2026, 10, 16, 2, 30),
    );
  });

  test('arrival plus 50 minutes rolls over midnight in Bangkok', () async {
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
    final applied = await controller.applyConfirmedFlight(
      flightNumber: 'TG401',
      flightDate: '2026-10-15',
      arrivalAirportCode: 'BKK',
      arrivalTimestamp: '2026-10-16T16:30:00Z',
    );
    expect(applied, isTrue);
    expect(controller.state.pickupDate, '2026-10-17');
    expect(controller.state.pickupTime, '00:20');
  });

  testWidgets('opposite endpoint is excluded from recent places', (
    tester,
  ) async {
    const origin = LocationOption(
      id: 'place:origin',
      placeId: 'origin',
      displayName: 'Selected origin',
      kind: LocationKind.place,
    );
    const other = LocationOption(
      id: 'place:other',
      placeId: 'other',
      displayName: 'Other recent place',
      kind: LocationKind.place,
    );
    final storage = RecentLocationsStorage(
      guestRepository: _NoopRecentRepository(const [origin, other]),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: Scaffold(
            body: GooglePlacesSearchField(
              label: 'Destination',
              languageCode: 'en',
              excludedRecentLocation: origin,
              recentLocationsStorage: storage,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selected origin'), findsNothing);
    expect(find.text('Other recent place'), findsOneWidget);
  });

  testWidgets('confirmed step-one flight number is prefilled in step two', (
    tester,
  ) async {
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
    await controller.applyConfirmedFlight(
      flightNumber: 'tg401',
      flightDate: '2026-10-15',
      arrivalAirportCode: 'BKK',
      arrivalTimestamp: '2026-10-15T19:30:00Z',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: Scaffold(
            body: StepPickupDateTime(
              state: controller.state,
              controller: controller,
              onFlightNumberChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('flight_number_field')),
    );
    expect(field.controller?.text, 'TG401');
  });
}
