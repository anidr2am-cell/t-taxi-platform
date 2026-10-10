import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_trip_contact.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/widgets/driver_customer_contact_card.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('customerContact parses nullable response fields', () {
    final booking = DriverBooking.fromJson({
      'bookingNumber': 'TX202610100001',
      'status': 'DRIVER_ASSIGNED',
      'serviceType': {'name': 'Airport Pickup'},
      'vehicleType': {'name': 'Sedan'},
      'passengerCount': 1,
      'customerPhone': null,
      'customerContact': {
        'messengerType': 'line',
        'messengerId': ' line-user ',
        'phone': null,
      },
    });

    expect(booking.customerPhone, isNull);
    expect(booking.customerContact?.messengerType, 'LINE');
    expect(booking.customerContact?.messengerId, 'line-user');
    expect(booking.customerContact?.phone, isNull);
  });

  test(
    'contact URI helpers reject empty values and normalize E.164 numbers',
    () {
      expect(DriverTripContact.whatsappUri(null), isNull);
      expect(DriverTripContact.smsUri(''), isNull);
      expect(
        DriverTripContact.whatsappUri('+82 10-1234-5678').toString(),
        'https://wa.me/821012345678',
      );
      expect(
        DriverTripContact.smsUri('+66 81 234 5678').toString(),
        'sms:+66812345678',
      );
      expect(
        DriverTripContact.samePhone('+82 10-1234-5678', '+821012345678'),
        isTrue,
      );
    },
  );

  for (final locale in AppLocalizations.supportedLanguages) {
    testWidgets('contact card renders at 375px in $locale', (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          locale,
          const DriverCustomerContactCard(
            contact: DriverCustomerContact(
              messengerType: 'KAKAO',
              messengerId: 'trider-user',
              phone: '+66812345678',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('driverCustomerMessenger')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driverCustomerEmergencyPhone')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('WhatsApp phone is not duplicated as emergency phone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        'en',
        const DriverCustomerContactCard(
          contact: DriverCustomerContact(
            messengerType: 'WHATSAPP',
            messengerId: '+821012345678',
            phone: '+82 10-1234-5678',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driverCustomerMessenger')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('driverCustomerEmergencyPhone')),
      findsNothing,
    );
  });

  testWidgets('legacy phone and missing contact have explicit fallbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        'en',
        const Column(
          children: [
            DriverCustomerContactCard(
              contact: null,
              legacyPhone: '+66812345678',
            ),
            DriverCustomerContactCard(contact: null),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driverCustomerLegacyPhone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('driverCustomerContactUnavailable')),
      findsOneWidget,
    );
  });
}

Widget _wrap(String locale, Widget child) {
  return MaterialApp(
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
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}
