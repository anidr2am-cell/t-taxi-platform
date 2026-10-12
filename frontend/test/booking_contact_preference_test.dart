import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/utils/booking_contact_preference.dart';
import 'package:frontend/features/booking/widgets/booking_contact_preference_section.dart';
import 'package:frontend/l10n/app_localizations.dart';

import 'support/booking_wizard_test_helpers.dart';

class _ContactHarness extends StatefulWidget {
  const _ContactHarness();

  @override
  State<_ContactHarness> createState() => _ContactHarnessState();
}

class _ContactHarnessState extends State<_ContactHarness> {
  BookingWizardState state = const BookingWizardState(
    messengerType: BookingContactPreference.kakao,
    customerCountryCode: '+82',
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: BookingContactPreferenceSection(
        state: state,
        onTypeChanged: (value) => setState(() {
          state = state.copyWith(messengerType: value, messengerId: '');
        }),
        onMessengerIdChanged: (value) => setState(() {
          state = state.copyWith(messengerId: value);
        }),
        onPhoneChanged: (value) => setState(() {
          state = state.copyWith(customerPhone: value);
        }),
        onDialCodeChanged: (value) => setState(() {
          state = state.copyWith(customerCountryCode: value);
        }),
        loginPrompt: const Text('LOGIN_ACTION'),
      ),
    );
  }
}

Widget _app(Widget child, {String languageCode = 'ko'}) => MaterialApp(
  locale: Locale(languageCode),
  localizationsDelegates: [
    AppLocalizationsDelegate(languageCode),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLanguages
      .map(Locale.new)
      .toList(),
  home: Scaffold(body: child),
);

void main() {
  test('normalizes legacy contact labels', () {
    expect(BookingContactPreference.normalize('kakao talk'), 'KAKAO');
    expect(BookingContactPreference.normalize('line'), 'LINE');
    expect(BookingContactPreference.normalize('WhatsApp'), 'WHATSAPP');
    expect(BookingContactPreference.normalize('phone'), 'SMS');
  });

  test('chooses auth provider before locale default', () {
    expect(
      BookingContactPreference.defaultFor(
        languageCode: 'en',
        authProvider: 'KAKAO',
      ),
      'KAKAO',
    );
    expect(
      BookingContactPreference.defaultFor(
        languageCode: 'ko',
        authProvider: 'LINE',
      ),
      'LINE',
    );
  });

  test('uses locale contact and dial code defaults', () {
    expect(BookingContactPreference.defaultFor(languageCode: 'ko'), 'KAKAO');
    expect(BookingContactPreference.defaultFor(languageCode: 'th'), 'LINE');
    expect(BookingContactPreference.defaultFor(languageCode: 'ja'), 'LINE');
    expect(BookingContactPreference.defaultFor(languageCode: 'en'), 'WHATSAPP');
    expect(BookingContactPreference.defaultFor(languageCode: 'zh'), 'WHATSAPP');
    expect(BookingContactPreference.defaultDialCode('ko'), '+82');
    expect(BookingContactPreference.defaultDialCode('en'), '+66');
  });

  test('contact preference copy exists in every supported language', () {
    for (final language in AppLocalizations.supportedLanguages) {
      final l10n = AppLocalizations(language);
      for (final key in [
        'booking_contact_method_title',
        'booking_contact_phone_sms',
        'booking_contact_method_summary',
        'booking_contact_emergency_summary',
        'booking_contact_kakao_id_optional',
        'booking_contact_kakao_phone_required',
        'booking_contact_kakao_phone_help',
        'booking_contact_confirm_kakao',
        'booking_contact_confirm_line',
        'admin_contact_unverified',
      ]) {
        expect(
          l10n.t(key),
          isNot(key),
          reason: '$language must translate $key',
        );
      }
    }
  });

  test('normalizes international phone numbers', () {
    expect(
      BookingContactPreference.normalizeInternationalPhone(
        '+66',
        '081-234-5678',
      ),
      '+66812345678',
    );
    expect(
      BookingContactPreference.normalizeInternationalPhone('TH', '0812345678'),
      '+66812345678',
    );
    expect(
      BookingContactPreference.normalizeInternationalPhone('+66', '123'),
      '',
    );
    expect(
      BookingContactPreference.normalizeInternationalPhone(
        '+82',
        '010-1234-5678',
      ),
      '+821012345678',
    );
    expect(
      BookingContactPreference.formatInternationalPhone('+821012345678'),
      '+82 10-1234-5678',
    );
  });

  testWidgets('shows all four choices and channel-specific inputs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const _ContactHarness()));
    await tester.pumpAndSettle();

    for (final type in BookingContactPreference.values) {
      expect(
        find.byKey(ValueKey('booking-contact-$type'), skipOffstage: false),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('booking-messenger-id')), findsOneWidget);
    expect(find.byKey(const ValueKey('booking-contact-phone')), findsOneWidget);
    expect(find.text('LOGIN_ACTION'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('booking-contact-phone')),
      '010-1234-5678',
    );

    final card = tester.getSize(
      find.byKey(const ValueKey('booking-contact-KAKAO')),
    );
    expect(card.height, inInclusiveRange(64, 72));

    final whatsapp = find.byKey(
      const ValueKey('booking-contact-WHATSAPP'),
      skipOffstage: false,
    );
    await tester.ensureVisible(whatsapp);
    await tester.tap(whatsapp);
    await tester.pump();

    expect(find.byKey(const ValueKey('booking-messenger-id')), findsNothing);
    expect(find.byKey(const ValueKey('booking-contact-phone')), findsOneWidget);
    expect(find.text('010-1234-5678'), findsOneWidget);
    expect(find.text('LOGIN_ACTION'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final languageCode in AppLocalizations.supportedLanguages) {
    testWidgets(
      'Kakao phone guidance wraps without overflow at 375px in $languageCode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(375, 812));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _app(const _ContactHarness(), languageCode: languageCode),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations(languageCode);
        final helper = find.text(l10n.t('booking_contact_kakao_phone_help'));
        expect(helper, findsOneWidget);
        await tester.ensureVisible(helper);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('booking-contact-phone')),
        );
        expect(field.decoration?.helperMaxLines, 3);
      },
    );
  }

  test('Kakao contact requires a phone and keeps its ID optional', () async {
    final controller = await buildContractAirportPickupController();
    await controller.updateCustomerInfo(
      name: 'QA Customer',
      phone: '',
      messengerType: 'KAKAO',
      messengerId: 'qa_kakao',
    );

    expect(
      controller.safeEntryStep(controller.state, BookingWizardSteps.review),
      BookingWizardSteps.customer,
    );

    await controller.updateCustomerInfo(
      phone: '010-1234-5678',
      countryCode: '+82',
      messengerId: '',
    );
    expect(
      controller.safeEntryStep(controller.state, BookingWizardSteps.review),
      BookingWizardSteps.review,
    );
    final customer = controller.buildCreatePayload()['customer'] as Map;
    expect(customer['phone'], '+821012345678');
    expect(customer['messengerType'], 'KAKAO');
    expect(customer.containsKey('messengerId'), isFalse);
  });
}
