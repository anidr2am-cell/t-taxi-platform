import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/utils/booking_contact_preference.dart';
import 'package:frontend/features/booking/widgets/step_customer_info.dart';
import 'support/booking_wizard_test_helpers.dart';

void main() {
  test('Russian is available by URL and customer language menu', () {
    expect(AppLocalizations.customerSupportedLanguages, contains('ru'));
    expect(AppLocalizations.supportedLanguages, isNot(contains('ru')));
    expect(AppLocalizations.languageNames['ru'], 'Русский');
    expect(
      LocaleState(
        entryUri: Uri.parse('https://example.test/booking?lang=ru'),
      ).languageCode,
      'ru',
    );
    expect(BookingContactPreference.defaultDialCode('ru'), '+7');
    expect(
      BookingContactPreference.normalizeInternationalPhone('+7', '9161234567'),
      '+79161234567',
    );
  });

  test(
    'all customer booking keys have explicit Russian text and retain placeholders',
    () {
      final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
      final keyPattern = RegExp(r'''['"]([a-zA-Z][a-zA-Z_0-9]+)['"]\s*:''');
      final allKeys = keyPattern.allMatches(source).map((m) => m[1]!).toSet();
      final russianBlock = source
          .split('_customerRussianTranslations = {')[1]
          .split('\n  };')[0];
      final ruKeys = keyPattern
          .allMatches(russianBlock)
          .map((m) => m[1]!)
          .toSet();
      final files = [
        ...Directory('lib/features/booking').listSync(recursive: true),
        ...Directory('lib/features/support').listSync(recursive: true),
        ...Directory('lib/widgets').listSync(),
        ...Directory('lib/screens/booking').listSync(recursive: true),
      ].whereType<File>().where((f) => f.path.endsWith('.dart'));
      final used = <String>{};
      final stringPattern = RegExp(r'''['"]([a-zA-Z][a-zA-Z_0-9]+)['"]''');
      for (final file in files) {
        used.addAll(
          stringPattern
              .allMatches(file.readAsStringSync())
              .map((m) => m[1]!)
              .where(allKeys.contains),
        );
      }
      used.removeAll({'en', 'ko', 'th', 'ja', 'zh', 'ru'});
      expect(
        used.difference(ruKeys),
        isEmpty,
        reason: 'Customer keys must not silently fall back to English',
      );
      final placeholders = RegExp(r'\{\w+\}');
      for (final key in ruKeys) {
        final ru = AppLocalizations('ru').t(key);
        expect(ru, isNot(key), reason: key);
        expect(
          placeholders.allMatches(ru).map((m) => m[0]).toSet(),
          placeholders
              .allMatches(AppLocalizations('en').t(key))
              .map((m) => m[0])
              .toSet(),
          reason: key,
        );
      }
    },
  );

  test(
    'Russian phone and locale reach the booking payload and survive draft restore',
    () async {
      final api = CapturingBookingApi();
      final c = await buildContractAirportPickupController(api: api);
      await c.updateCustomerInfo(
        name: 'Иван',
        messengerType: 'TELEGRAM',
        phone: '9161234567',
        countryCode: '+7',
        email: 'qa@example.invalid',
      );
      // The capturing API stops after recording the request; no booking is made.
      await c.submitBooking(locale: 'ru');
      final payload = api.lastCreateRequest!;
      expect(payload['locale'], 'ru');
      expect((payload['customer'] as Map)['phone'], '+79161234567');
      final restored = BookingWizardState.fromJson(c.state.toJson());
      expect(restored.customerCountryCode, '+7');
      expect(restored.customerName, 'Иван');
      expect(c.canProceedFromStep(3), isTrue);
    },
  );

  testWidgets('Russian contact form and validation fit 375px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var state = const BookingWizardState(
      customerName: 'Иван',
      messengerType: 'TELEGRAM',
      customerCountryCode: '+7',
      customerPhone: '9161234567',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.customerSupportedLanguages
            .map(Locale.new)
            .toList(),
        localizationsDelegates: [
          AppLocalizationsDelegate('ru'),
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
              onMessengerTypeChanged: (_) {},
              onMessengerIdChanged: (_) {},
              onAdditionalRequestsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+7'), findsOneWidget);
    final email = find.byKey(const ValueKey('booking-customer-email'));
    await tester.ensureVisible(email);
    await tester.enterText(email, 'invalid');
    await tester.pump();
    expect(
      find.text(AppLocalizations('ru').t('booking_email_invalid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
