import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/utils/booking_contact_preference.dart';
import 'package:frontend/features/booking/widgets/booking_contact_preference_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/calling_countries.dart';

class ContactHarness extends StatefulWidget {
  const ContactHarness({super.key});
  @override
  State<ContactHarness> createState() => _ContactHarnessState();
}

class _ContactHarnessState extends State<ContactHarness> {
  BookingWizardState state = const BookingWizardState(
    messengerType: 'WHATSAPP',
    customerCountryCode: '+44',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      child: BookingContactPreferenceSection(
        state: state,
        onTypeChanged: (v) =>
            setState(() => state = state.copyWith(messengerType: v)),
        onMessengerIdChanged: (v) {},
        onPhoneChanged: (v) =>
            setState(() => state = state.copyWith(customerPhone: v)),
        onDialCodeChanged: (v) =>
            setState(() => state = state.copyWith(customerCountryCode: v)),
      ),
    ),
  );
}

void main() {
  test('shared worldwide list retains 245 countries and 206 calling codes', () {
    expect(callingCountries.length, 245);
    expect(callingCodes.length, 206);
    for (final code in ['+44', '+91', '+61', '+49', '+971', '+998', '+1']) {
      expect(callingCodes, contains(code));
    }
  });
  for (final lang in AppLocalizations.customerSupportedLanguages) {
    testWidgets('WhatsApp worldwide search and selection fit 375px $lang', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          supportedLocales: AppLocalizations.customerSupportedLanguages
              .map(Locale.new)
              .toList(),
          localizationsDelegates: [
            AppLocalizationsDelegate(lang),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ContactHarness(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('+44'),
        findsOneWidget,
      ); // Do not silently substitute +66.
      await tester.tap(find.byKey(const ValueKey('booking-phone-dial-code')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('adminCallingCountrySearch'));
      for (final query in ['India', '+91']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('adminCallingCountry-IN')),
          findsOneWidget,
        );
      }
      await tester.enterText(search, '+1');
      await tester.pumpAndSettle();
      // Shared calling codes are kept as distinct countries, not duplicate dropdown values.
      expect(
        callingCountries.where((c) => c.dialCode == '+1').map((c) => c.code),
        containsAll(['US', 'CA']),
      );
      await tester.enterText(search, 'United Kingdom');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adminCallingCountry-GB')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('booking-contact-phone')),
        '794625934',
      );
      final harness = tester.state<_ContactHarnessState>(
        find.byType(ContactHarness),
      );
      expect(
        BookingContactPreference.contactPhone(
          'WHATSAPP',
          harness.state.customerCountryCode,
          harness.state.customerPhone,
        ),
        '+44794625934',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
