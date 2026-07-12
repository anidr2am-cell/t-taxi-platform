import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/country_option.dart';
import 'package:frontend/features/booking/widgets/step_customer_info.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test(
    'country aliases find South Korea and selected values normalize to KR',
    () {
      for (final query in [
        'korea',
        'south korea',
        '한국',
        '대한민국',
        'เกาหลี',
        'เกาหลีใต้',
      ]) {
        final matches = CountryCatalog.search(query).toList();
        expect(matches, isNotEmpty, reason: query);
        expect(matches.first.code, 'KR', reason: query);
      }
    },
  );

  test(
    'ISO country codes display in the current locale and free text survives',
    () {
      expect(CountryCatalog.displayName('KR', AppLocalizations('ko')), '대한민국');
      expect(
        CountryCatalog.displayName('KR', AppLocalizations('en')),
        'South Korea',
      );
      expect(
        CountryCatalog.displayName('KR', AppLocalizations('th')),
        'เกาหลีใต้',
      );
      expect(
        CountryCatalog.displayName('korea', AppLocalizations('en')),
        'korea',
      );
      expect(CountryCatalog.displayName('', AppLocalizations('en')), '');
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'country suggestions select KR without overflow at ${width.toInt()}px',
      (tester) async {
        String? savedCountry;
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StepCustomerInfo(
                state: const BookingWizardState(),
                onNameChanged: (_) {},
                onEmailChanged: (_) {},
                onPhoneChanged: (_) {},
                onCountryChanged: (value) => savedCountry = value,
                onMessengerTypeChanged: (_) {},
                onMessengerIdChanged: (_) {},
                onAdditionalRequestsChanged: (_) {},
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(EditableText).at(3), 'korea');
        await tester.pumpAndSettle();
        expect(find.text('South Korea'), findsOneWidget);
        await tester.tap(find.text('South Korea'));
        await tester.pumpAndSettle();

        expect(savedCountry, 'KR');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('country field keeps free text and allows empty values', (
    tester,
  ) async {
    String? savedCountry;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StepCustomerInfo(
            state: const BookingWizardState(),
            onNameChanged: (_) {},
            onEmailChanged: (_) {},
            onPhoneChanged: (_) {},
            onCountryChanged: (value) => savedCountry = value,
            onMessengerTypeChanged: (_) {},
            onMessengerIdChanged: (_) {},
            onAdditionalRequestsChanged: (_) {},
          ),
        ),
      ),
    );

    final countryField = find.byType(EditableText).at(3);
    await tester.enterText(countryField, 'Atlantis');
    expect(savedCountry, 'Atlantis');
    await tester.enterText(countryField, '');
    expect(savedCountry, '');
  });
}
