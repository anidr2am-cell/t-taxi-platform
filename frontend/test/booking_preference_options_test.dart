import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/widgets/step_confirmation.dart';
import 'package:frontend/features/booking/widgets/step_passengers_luggage.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_wizard_test_helpers.dart';

class _NoopStorage extends BookingStateStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<BookingWizardState?> load() async => null;

  @override
  Future<void> save(BookingWizardState state) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookingWizardController preference options', () {
    test('buildCreatePayload reflects toggle on/off', () async {
      final controller = await buildContractAirportPickupController();

      var payload = controller.buildCreatePayload();
      expect(payload['options'], {
        'nameSign': true,
        'nameSignText': 'KIM FAMILY',
        'preferFemaleDriver': false,
      });

      await controller.updatePassengersAndLuggage(
        preferFemaleDriver: true,
      );
      payload = controller.buildCreatePayload();
      expect(payload['options'], {
        'nameSign': true,
        'nameSignText': 'KIM FAMILY',
        'preferFemaleDriver': true,
      });

      await controller.updatePassengersAndLuggage(
        preferFemaleDriver: false,
      );
      payload = controller.buildCreatePayload();
      expect(payload['options'], {
        'nameSign': true,
        'nameSignText': 'KIM FAMILY',
        'preferFemaleDriver': false,
      });
    });
  });

  group('BookingStateStorage preference options', () {
    test('persists and restores preferFemaleDriver', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = BookingStateStorage(now: () => DateTime.utc(2026, 7, 1, 8));
      const state = BookingWizardState(
        preferFemaleDriver: true,
      );

      await storage.save(state);
      final restored = await storage.load();

      expect(restored?.preferFemaleDriver, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(
        prefs.getString(BookingStateStorage.draftStorageKey)!,
      ) as Map<String, dynamic>;
      final stateJson = Map<String, dynamic>.from(decoded['state'] as Map);
      expect(stateJson['preferFemaleDriver'], isTrue);
    });
  });

  group('StepConfirmation preference summary', () {
    Future<void> pumpConfirmation(
      WidgetTester tester, {
      required BookingWizardState state,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            home: Scaffold(body: StepConfirmation(state: state)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows selected preference options', (tester) async {
      await pumpConfirmation(
        tester,
        state: const BookingWizardState(
          preferFemaleDriver: true,
        ),
      );

      expect(find.text('Prefer Female Driver'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
    });

    testWidgets('hides preference rows when toggles are off', (tester) async {
      await pumpConfirmation(
        tester,
        state: const BookingWizardState(),
      );

      expect(find.text('Prefer Female Driver'), findsNothing);
    });
  });

  group('StepPassengersLuggage preference toggles', () {
    Future<void> pumpPassengerStep(
      WidgetTester tester, {
      required String languageCode,
      BookingWizardController? controller,
    }) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final activeController =
          controller ?? BookingWizardController(storage: _NoopStorage());
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState()..setLanguage(languageCode),
          child: MaterialApp(
            locale: Locale(languageCode),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StepPassengersLuggage(
                  state: activeController.state,
                  controller: activeController,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows disclaimer under preference toggle', (tester) async {
      await pumpPassengerStep(tester, languageCode: 'en');

      final disclaimer =
          AppLocalizations('en').t('booking_preference_disclaimer');
      expect(find.text(disclaimer), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(2));
    });

    for (final code in AppLocalizations.supportedLanguages) {
      testWidgets('renders without overflow for locale $code', (tester) async {
        await pumpPassengerStep(tester, languageCode: code);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
