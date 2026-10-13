import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/pages/driver_support_page.dart';
import 'package:frontend/features/driver/widgets/driver_customer_contact_card.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('driver booking accepts redacted contact fields', () {
    final booking = DriverBooking.fromJson({
      'bookingNumber': 'TX202610100001',
      'status': 'DRIVER_ASSIGNED',
      'serviceType': {'name': 'Airport Pickup'},
      'vehicleType': {'name': 'Sedan'},
      'passengerCount': 1,
      'customerPhone': null,
      'customerEmail': null,
      'customerContact': null,
    });

    expect(booking.customerPhone, isNull);
    expect(booking.customerContact, isNull);
  });

  for (final locale in AppLocalizations.supportedLanguages) {
    testWidgets('administrator-only contact card fits 375px in $locale', (
      tester,
    ) async {
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
              messengerId: 'must-not-render',
              phone: '+66812345678',
            ),
            legacyPhone: '+66999999999',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '고객 연락은 관리자를 통해 진행합니다.\n'
          '(การติดต่อลูกค้าดำเนินการผ่านผู้ดูแล)',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driverCustomerContactAdminButton')),
        findsOneWidget,
      );
      expect(find.textContaining('must-not-render'), findsNothing);
      expect(find.textContaining('+66812345678'), findsNothing);
      expect(find.textContaining('+66999999999'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('administrator contact button opens existing support flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap('ko', const DriverCustomerContactCard(contact: null)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('driverCustomerContactAdminButton')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DriverSupportPage), findsOneWidget);
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
