import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/utils/booking_status_display.dart';
import 'package:frontend/features/booking/utils/customer_booking_format.dart';
import 'package:frontend/features/booking/widgets/booking_contact_preference_section.dart';
import 'package:frontend/features/booking/widgets/customer_payment_instructions_card.dart';
import 'package:frontend/features/booking/widgets/booking_messenger_handoff_section.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';

class _WeChatChannels extends BookingContactConnectionService {
  @override
  Future<List<ContactChannel>> getPublicChannels() async => const [
    ContactChannel(code: 'WECHAT', displayName: 'WeChat', accountId: 'QA_ONLY'),
  ];
}

Widget wrap(String language, Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  locale: Locale(language),
  supportedLocales: AppLocalizations.customerSupportedLanguages
      .map(Locale.new)
      .toList(),
  localizationsDelegates: [
    AppLocalizationsDelegate(language),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['NotoSans', 'NotoSansThai']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  for (final language in AppLocalizations.customerSupportedLanguages) {
    final l10n = AppLocalizations(language);
    test(
      '$language resolves customer labels and separates assignment from departure',
      () {
        for (final key in [
          'guest_lookup_mode_booking_number',
          'guest_lookup_mode_contact_name',
          'guest_lookup_name',
          'guest_lookup_contact_subtitle',
          'guest_lookup_contact_back_to_list',
          'guest_lookup_contact_detail_guidance',
          'guest_lookup_contact_results_title',
          'guest_lookup_inquiry_channels_hint',
          'guest_lookup_invalid_name',
          'guest_lookup_luggage',
          'guest_lookup_passengers',
          'guest_lookup_pickup_period_afternoon',
          'guest_lookup_pickup_period_evening',
          'guest_lookup_pickup_period_morning',
          'customer_payment_bank_name',
          'customer_payment_account_holder',
          'customer_payment_account_number',
          'support_close_button',
        ]) {
          expect(l10n.t(key), isNot(key));
          if (language != 'en')
            expect(l10n.t(key), isNot(AppLocalizations('en').t(key)));
        }
        expect(
          CustomerBookingFormat.vehicle(l10n, 'SEDAN'),
          l10n.t('cx_vehicle_SEDAN'),
        );
        expect(
          CustomerBookingFormat.vehicle(l10n, 'HISTORIC_TYPE'),
          'HISTORIC_TYPE',
        );
        expect(CustomerBookingFormat.vehicle(l10n, null), '-');
        expect(
          BookingStatusDisplay.customerGuidance(l10n, 'DRIVER_ASSIGNED'),
          l10n.t('guest_status_guidance_driver_assigned'),
        );
        expect(
          BookingStatusDisplay.customerGuidance(l10n, 'DRIVER_ASSIGNED'),
          isNot(BookingStatusDisplay.customerGuidance(l10n, 'ON_ROUTE')),
        );
        expect(l10n.t('flight_number_hint'), 'TG401');
      },
    );
    testWidgets('$language phone guidance wraps outside the input at 375px', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        wrap(
          language,
          BookingContactPreferenceSection(
            state: const BookingWizardState(
              messengerType: 'LINE',
              customerCountryCode: '+66',
            ),
            onTypeChanged: (_) {},
            onMessengerIdChanged: (_) {},
            onPhoneChanged: (_) {},
            onDialCodeChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('booking-contact-phone')),
      );
      expect(input.decoration!.labelText, l10n.t('phone'));
      expect(input.decoration!.hintText, isNull);
      final guidance = find.text(l10n.t('booking_contact_phone_hint'));
      expect(guidance, findsOneWidget);
      expect(tester.widget<Text>(guidance).maxLines, isNull);
      expect(tester.getSize(guidance).width, greaterThan(250));
      expect(find.text(l10n.t('contact_phone_required_help')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$language KRW instructions use customer translations', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          language,
          const CustomerPaymentInstructionsCard(
            paymentMethod: 'BANK_TRANSFER',
            paymentCurrency: 'KRW',
            instructions: {
              'bankName': 'QA BANK',
              'accountName': 'QA HOLDER',
              'accountNumber': 'QA NUMBER',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'customer_payment_bank_name',
        'customer_payment_account_holder',
        'customer_payment_account_number',
      ]) {
        expect(find.text(l10n.t(key)), findsOneWidget);
      }
      expect(find.text('QA BANK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$language WeChat dialog has a localized close action', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        wrap(
          language,
          BookingMessengerHandoffSection(
            bookingNumber: 'QA_ONLY',
            service: _WeChatChannels(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('booking_handoff_wechat'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(l10n.t('support_close_button')), findsOneWidget);
      expect(find.text('close'), findsNothing);
    });
  }
  test('English suitcase terminology and unknown payment are actionable', () {
    final l10n = AppLocalizations('en');
    expect(l10n.t('small_carriers'), '20″ suitcases');
    expect(l10n.t('large_carriers'), '24″+ suitcases');
    expect(
      CustomerBookingFormat.paymentMethod(l10n, null),
      'Please confirm the payment method',
    );
    expect(
      CustomerBookingFormat.paymentMethod(AppLocalizations('zh'), null),
      '请确认付款方式',
    );
  });
}
