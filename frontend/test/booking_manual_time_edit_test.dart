import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/widgets/step_pickup_datetime.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Memory extends BookingStateStorage {
  @override
  Future<void> save(BookingWizardState state) async {}
  @override
  Future<BookingWizardState?> load() async => null;
}

void main() {
  for (final locale in ['ko', 'en']) {
    for (final service in [
      BookingServiceType.cityTransfer,
      BookingServiceType.airportPickup,
    ]) {
      testWidgets(
        '$locale $service preserves unfinished minute and syncs picker changes',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final controller = BookingWizardController(
            storage: _Memory(),
            now: () => DateTime(2026, 12, 1),
          );
          await controller.initialize(initialServiceType: service);
          await controller.setPickupDate(DateTime(2026, 12, 10));
          await controller.setPickupTime(hour24: 22, minute: 10);
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => LocaleState()..setLanguage(locale),
              child: MaterialApp(
                locale: Locale(locale),
                supportedLocales: const [Locale('ko'), Locale('en')],
                localizationsDelegates: [
                  AppLocalizationsDelegate(locale),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(
                  body: AnimatedBuilder(
                    animation: controller,
                    builder: (_, __) => StepPickupDateTime(
                      state: controller.state,
                      controller: controller,
                      onFlightNumberChanged:
                          service == BookingServiceType.airportPickup
                          ? (_) {}
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (service == BookingServiceType.airportPickup) {
            await tester.tap(find.byKey(const Key('schedule_method_manual')));
            await tester.pumpAndSettle();
          }
          final expander = find.byKey(const Key('manual_time_expander'));
          await tester.ensureVisible(expander);
          await tester.tap(expander);
          await tester.pumpAndSettle();
          final field = find.byKey(const Key('pickup_manual_time_field'));
          await tester.ensureVisible(field);
          await tester.tap(field);
          for (final minute in ['00', '05']) {
            await tester.enterText(field, '22:0');
            await tester.pumpAndSettle();
            final input = tester.widget<TextField>(field).controller!;
            expect(
              input.text,
              '22:0',
              reason:
                  'An onChanged rebuild must not replace the draft with 10:00 PM / 22:00.',
            );
            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: input.text + minute[1],
                selection: const TextSelection.collapsed(offset: 5),
              ),
            );
            await tester.pumpAndSettle();
            expect(input.text, '22:$minute');
            expect(controller.state.pickupTime, '22:$minute');
          }
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await controller.setPickupTime(hour24: 20, minute: 15);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(field).controller!.text,
            locale == 'ko' ? '20:15' : '08:15 PM',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        },
      );
    }
  }
}
