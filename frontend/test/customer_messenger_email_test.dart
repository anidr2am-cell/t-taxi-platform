import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/widgets/step_customer_info.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/utils/booking_contact_preference.dart';
import 'support/booking_wizard_test_helpers.dart';

void main() {
  for (final locale in ['ko', 'en', 'th', 'ja', 'zh']) {
    testWidgets('messenger dropdown and optional email fit 375px: $locale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var state = const BookingWizardState(
        customerName: 'QA',
        messengerType: 'WECHAT',
        customerCountryCode: '+82',
        customerPhone: '01012345678',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLanguages
              .map(Locale.new)
              .toList(),
          localizationsDelegates: [
            AppLocalizationsDelegate(locale),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => StepCustomerInfo(
                state: state,
                onNameChanged: (_) {},
                onEmailChanged: (v) =>
                    setState(() => state = state.copyWith(customerEmail: v)),
                onPhoneChanged: (_) {},
                onCountryChanged: (_) {},
                onMessengerTypeChanged: (v) =>
                    setState(() => state = state.copyWith(messengerType: v)),
                onMessengerIdChanged: (_) {},
                onAdditionalRequestsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('booking-customer-email'));
      await tester.ensureVisible(field);
      expect(
        find.text(AppLocalizations(locale).t('booking_email_explanation')),
        findsOneWidget,
      );
      await tester.enterText(field, 'bad-address');
      await tester.pump();
      expect(
        find.text(AppLocalizations(locale).t('booking_email_invalid')),
        findsOneWidget,
      );
      await tester.enterText(field, 'qa@example.invalid');
      await tester.pump();
      expect(
        find.text(AppLocalizations(locale).t('booking_email_invalid')),
        findsNothing,
      );
      expect(state.customerEmail, 'qa@example.invalid');
      expect(tester.takeException(), isNull);
    });
  }
  for (final type in ['WECHAT', 'TELEGRAM'])
    test(
      '$type persists optional email, E.164 phone and draft values',
      () async {
        final c = await buildContractAirportPickupController();
        await c.updateCustomerInfo(
          name: 'QA',
          messengerType: type,
          messengerId: '',
          phone: '01012345678',
          countryCode: '+82',
          email: ' qa@example.invalid ',
        );
        expect(c.canProceedFromStep(BookingWizardSteps.customer), isTrue);
        final customer = c.buildCreatePayload()['customer'] as Map;
        expect(customer['email'], 'qa@example.invalid');
        expect(customer['phone'], '+821012345678');
        expect(customer['messengerType'], type);
        final restored = BookingWizardState.fromJson(c.state.toJson());
        expect(restored.customerEmail, c.state.customerEmail);
        expect(restored.messengerType, type);
        await c.updateCustomerInfo(email: 'invalid');
        expect(c.canProceedFromStep(BookingWizardSteps.customer), isFalse);
        await c.updateCustomerInfo(email: '', phone: '');
        expect(c.canProceedFromStep(BookingWizardSteps.customer), isFalse);
      },
    );
  test(
    'SMS historical labels stay readable but are never offered as a new selection',
    () {
      expect(BookingContactPreference.normalize('SMS'), 'SMS');
      expect(BookingContactPreference.values, isNot(contains('SMS')));
      expect(BookingContactPreference.values.length, 5);
    },
  );
}
