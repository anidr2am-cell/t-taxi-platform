import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/utils/pickup_time_format.dart';
import 'package:frontend/features/booking/widgets/pickup_time_picker_sheet.dart';
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

class _NoopRecentLocations implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption location) async {}

  @override
  Future<List<LocationOption>> load() async => const [];
}

BookingWizardController _controller({
  BookingWizardState? draft,
  DateTime? now,
}) {
  return BookingWizardController(
    storage: _MemoryStorage(draft),
    recentLocationsStorage: RecentLocationsStorage(
      guestRepository: _NoopRecentLocations(),
    ),
    now: () => now ?? DateTime.parse('2026-10-10T10:00:00+07:00'),
  );
}

Widget _testApp(BookingWizardController controller) {
  return ChangeNotifierProvider(
    create: (_) => LocaleState()..setLanguage('ko'),
    child: MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => StepPickupDateTime(
            state: controller.state,
            controller: controller,
            embedded: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('date first then picker confirmation keeps selected date', (
    tester,
  ) async {
    final controller = _controller();
    await controller.initialize(
      initialServiceType: BookingServiceType.airportPickup,
    );
    await controller.setPickupDate(DateTime(2026, 10, 24));
    await tester.pumpWidget(_testApp(controller));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pickup_time_picker')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PickupTimePickerSheet),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.pickupDate, '2026-10-24');
    expect(controller.state.pickupTime, isNotNull);
  });

  testWidgets('manual time rejection is shown beside the input', (
    tester,
  ) async {
    final controller = _controller();
    await controller.initialize(
      initialServiceType: BookingServiceType.airportPickup,
    );
    await controller.setPickupDate(DateTime(2026, 10, 10));
    await tester.pumpWidget(_testApp(controller));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('pickup_manual_time_field')),
      '09:00',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('pickup_manual_time_field')),
    );
    expect(field.decoration?.errorText, isNotNull);
    expect(controller.state.pickupDate, '2026-10-10');
    expect(controller.state.pickupTime, isNull);
    expect(controller.canProceedFromStep(BookingWizardSteps.schedule), isFalse);
  });

  test('date first then manual 14:00 preserves date and stores time', () async {
    final controller = _controller();
    await controller.initialize(
      initialServiceType: BookingServiceType.airportPickup,
    );
    await controller.setPickupDate(DateTime(2026, 10, 24));

    final accepted = await controller.setPickupTime(hour24: 14, minute: 0);

    expect(accepted, isTrue);
    expect(controller.state.pickupDate, '2026-10-24');
    expect(controller.state.pickupTime, '14:00');
  });

  test('past time is rejected without changing the selected date', () async {
    final controller = _controller();
    await controller.initialize(
      initialServiceType: BookingServiceType.airportPickup,
    );
    await controller.setPickupDate(DateTime(2026, 10, 10));

    final accepted = await controller.setPickupTime(hour24: 9, minute: 0);

    expect(accepted, isFalse);
    expect(controller.state.pickupDate, '2026-10-10');
    expect(controller.state.pickupTime, isNull);
    expect(controller.state.errorMessage, 'pickup_date_past');
    expect(controller.canProceedFromStep(BookingWizardSteps.schedule), isFalse);
  });

  test(
    'time first then invalid date change is shown and blocks progress',
    () async {
      final controller = _controller(
        now: DateTime.parse('2026-10-10T23:50:00+07:00'),
      );
      await controller.initialize(
        initialServiceType: BookingServiceType.airportPickup,
      );
      expect(await controller.setPickupTime(hour24: 1, minute: 0), isTrue);
      expect(controller.state.pickupDate, '2026-10-11');

      final accepted = await controller.setPickupDate(DateTime(2026, 10, 10));

      expect(accepted, isFalse);
      expect(controller.state.pickupDate, '2026-10-10');
      expect(controller.state.pickupTime, '01:00');
      expect(controller.state.errorMessage, 'pickup_date_past');
      expect(
        controller.canProceedFromStep(BookingWizardSteps.schedule),
        isFalse,
      );
    },
  );

  test('manual parser accepts 24-hour and localized 12-hour input', () {
    expect(
      PickupTimeFormat.parseManualInput('14:00', amLabel: '오전', pmLabel: '오후'),
      (hour24: 14, minute: 0),
    );
    expect(
      PickupTimeFormat.parseManualInput(
        '02:00 오후',
        amLabel: '오전',
        pmLabel: '오후',
      ),
      (hour24: 14, minute: 0),
    );
  });

  test('valid draft restore keeps pickup date and time', () async {
    final controller = _controller(
      draft: const BookingWizardState(
        serviceType: BookingServiceType.airportPickup,
        pickupDate: '2026-10-24',
        pickupTime: '14:00',
      ),
    );

    await controller.initialize();

    expect(controller.state.pickupDate, '2026-10-24');
    expect(controller.state.pickupTime, '14:00');
  });

  test(
    'flight confirmation still applies Bangkok arrival plus 50 minutes',
    () async {
      final controller = _controller();
      await controller.initialize(
        initialServiceType: BookingServiceType.airportPickup,
      );

      final applied = await controller.applyConfirmedFlight(
        flightNumber: 'KE651',
        flightDate: '2026-10-15',
        arrivalAirportCode: 'BKK',
        arrivalTimestamp: '2026-10-16T16:30:00Z',
      );

      expect(applied, isTrue);
      expect(controller.state.pickupDate, '2026-10-17');
      expect(controller.state.pickupTime, '00:20');
    },
  );

  for (final serviceType in BookingServiceType.values) {
    test(
      '$serviceType keeps an explicitly selected date when time changes',
      () async {
        final controller = _controller();
        await controller.initialize(initialServiceType: serviceType);
        await controller.setPickupDate(DateTime(2026, 10, 24));

        expect(await controller.setPickupTime(hour24: 14, minute: 0), isTrue);
        expect(controller.state.pickupDate, '2026-10-24');
        expect(controller.state.pickupTime, '14:00');
      },
    );
  }
}
