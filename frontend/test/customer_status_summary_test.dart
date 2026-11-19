import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/utils/booking_status_display.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';

GuestBookingLookupResult booking(
  String status,
  String? vehicle, {
  bool driver = true,
}) => GuestBookingLookupResult.fromJson({
  'bookingNumber': 'QA_DISPLAY_ONLY',
  'status': status,
  'scheduledPickupAt': '2030-11-10T01:16:00+07:00',
  'serviceType': {'code': 'CITY_TRANSFER', 'name': 'City Transfer'},
  'route': {
    'origin': {'address': 'QA ORIGIN'},
    'destination': {'address': 'QA DESTINATION'},
  },
  'pricing': {'totalAmount': 1000, 'currency': 'THB', 'paymentMethod': 'CASH'},
  'guestAccess': {'token': 'QA_ONLY', 'expiresAt': '2031-01-01T00:00:00Z'},
  'capabilities': {},
  'canCancel': false,
  'cancellationBlockedReason': 'TRIP_STARTED',
  if (driver)
    'assignedDriver': {
      'name': 'QA DRIVER',
      'vehicle': {
        'typeName': vehicle,
        'color': 'QA COLOR',
        'plateNumber': 'QA PLATE',
      },
    },
});

Widget app(String language, GuestBookingLookupResult result) => MaterialApp(
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
  home: AuthScope(
    controller: createSignedOutAuthController(),
    child: GuestBookingLookupPage(initialResult: result),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final family in ['NotoSans', 'NotoSansThai']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  for (final language in AppLocalizations.customerSupportedLanguages) {
    for (final status in ['DRIVER_ASSIGNED', 'ON_ROUTE']) {
      for (final type in ['Sedan', 'SUV', 'Van']) {
        testWidgets(
          '$language $status $type: one guidance and localized driver summary at 375px',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(375, 812);
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });
            final result = booking(status, type);
            final l10n = AppLocalizations(language);
            await tester.pumpWidget(app(language, result));
            await tester.pumpAndSettle();
            final guidance = BookingStatusDisplay.customerGuidance(
              l10n,
              status,
            )!;
            expect(find.text(guidance), findsOneWidget);
            expect(
              find.text(
                'QA DRIVER · ${l10n.t('cx_vehicle_${type.toUpperCase()}')} · QA COLOR · QA PLATE',
              ),
              findsOneWidget,
            );
            final other = status == 'ON_ROUTE' ? 'DRIVER_ASSIGNED' : 'ON_ROUTE';
            expect(
              find.text(BookingStatusDisplay.customerGuidance(l10n, other)!),
              findsNothing,
            );
            expect(result.status, status);
            expect(result.vehicleType, type);
            expect(result.totalAmount, 1000);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final type in <String?>[null, '  ', 'Historic minibus']) {
    testWidgets(
      'driver summary preserves missing/legacy vehicle $type without a stray dash',
      (tester) async {
        await tester.pumpWidget(app('ko', booking('DRIVER_ASSIGNED', type)));
        await tester.pumpAndSettle();
        final label = type == 'Historic minibus'
            ? 'QA DRIVER · Historic minibus · QA COLOR · QA PLATE'
            : 'QA DRIVER · QA COLOR · QA PLATE';
        expect(find.text(label), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('unassigned driver retains the existing pending label', (
    tester,
  ) async {
    await tester.pumpWidget(
      app('ko', booking('CONFIRMED', 'Sedan', driver: false)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(AppLocalizations('ko').t('customer_driver_pending')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
