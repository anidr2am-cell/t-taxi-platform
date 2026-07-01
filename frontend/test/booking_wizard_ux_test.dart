import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/utils/pickup_time_format.dart';
import 'package:frontend/features/booking/widgets/name_sign_info_card.dart';
import 'package:frontend/features/booking/widgets/pickup_time_picker_sheet.dart';
import 'package:frontend/features/booking/widgets/step_origin_select.dart';
import 'package:frontend/features/booking/widgets/step_destination_select.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopStorage extends BookingStateStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<BookingWizardState?> load() async => null;

  @override
  Future<void> save(BookingWizardState state) async {}
}

class _MemoryRecentLocationsRepository implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption location) async {}

  @override
  Future<List<LocationOption>> load() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PickupTimeFormat', () {
    test('formats and parses 12-hour display', () {
      expect(
        PickupTimeFormat.formatDisplay(
          hour24: 9,
          minute: 30,
          amLabel: 'AM',
          pmLabel: 'PM',
        ),
        '09:30 AM',
      );
      expect(
        PickupTimeFormat.formatDisplay(
          hour24: 21,
          minute: 5,
          amLabel: 'AM',
          pmLabel: 'PM',
        ),
        '09:05 PM',
      );

      final parsed = PickupTimeFormat.parseManualInput(
        '9:30 PM',
        amLabel: 'AM',
        pmLabel: 'PM',
      );
      expect(parsed?.hour24, 21);
      expect(parsed?.minute, 30);
    });

    test('rejects invalid manual input', () {
      expect(
        PickupTimeFormat.parseManualInput('99:99 AM', amLabel: 'AM', pmLabel: 'PM'),
        isNull,
      );
    });
  });

  group('BookingWizardController customer validation', () {
    late BookingWizardController controller;

    setUp(() {
      controller = BookingWizardController(storage: _NoopStorage());
    });

    test('requires name, phone, and country but not email', () async {
      await controller.updateCustomerInfo(
        name: 'Jane',
        phone: '+66123456789',
        countryCode: 'TH',
      );
      expect(controller.canProceedFromStep(6), isTrue);
    });

    test('rejects invalid email when provided', () async {
      await controller.updateCustomerInfo(
        name: 'Jane',
        phone: '+66123456789',
        countryCode: 'TH',
        email: 'not-an-email',
      );
      expect(controller.canProceedFromStep(6), isFalse);
    });
  });

  group('service-specific airport shortcuts', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpStep(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
      await tester.pump();
    }

    testWidgets('airport pickup shows origin shortcuts only', (tester) async {
      await pumpStep(
        tester,
        StepOriginSelect(
          serviceType: BookingServiceType.airportPickup,
          selected: null,
          languageCode: 'en',
          onSelected: (_) {},
        ),
      );

      expect(find.text('BKK'), findsOneWidget);
      expect(find.text('DMK'), findsOneWidget);
    });

    testWidgets('airport dropoff hides origin shortcuts', (tester) async {
      await pumpStep(
        tester,
        StepOriginSelect(
          serviceType: BookingServiceType.airportDropoff,
          selected: null,
          languageCode: 'en',
          onSelected: (_) {},
        ),
      );

      expect(find.text('BKK'), findsNothing);
    });

    testWidgets('airport dropoff shows destination shortcuts', (tester) async {
      await pumpStep(
        tester,
        StepDestinationSelect(
          serviceType: BookingServiceType.airportDropoff,
          selected: null,
          languageCode: 'en',
          onSelected: (_) {},
        ),
      );

      expect(find.text('BKK'), findsOneWidget);
    });
  });

  group('name sign info card', () {
    testWidgets('hidden when disabled and visible when enabled', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: const MaterialApp(
            home: Scaffold(
              body: NameSignInfoCard(visible: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);

      final description = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((richText) => richText.text.toPlainText())
          .join(' ');
      expect(description, contains('100 THB'));
      expect(description, contains('Gate 3'));
    });
  });

  group('pickup time picker sheet', () {
    testWidgets('shows wheel picker without analog dial', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            home: Scaffold(
              body: PickupTimePickerSheet(
                initialHour24: 9,
                initialMinute: 30,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      expect(find.byType(TimePickerDialog), findsNothing);
    });
  });
}
