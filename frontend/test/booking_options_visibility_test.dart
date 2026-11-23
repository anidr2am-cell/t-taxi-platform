import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'support/booking_wizard_test_helpers.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';

class _UnavailableRecommendation extends CapturingBookingApi {
  @override
  Future<VehicleRecommendation> recommendVehicle({
    required int adults,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) async => throw Exception('QA recommendation unavailable');
}

void main() {
  for (final locale in ['ko', 'en', 'th', 'ja', 'zh', 'zh-TW', 'ru']) {
    for (final unavailable in [false, true]) {
      testWidgets(
        '$locale options start open and remain usable with recommendation unavailable=$unavailable',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final api = unavailable
              ? _UnavailableRecommendation()
              : CapturingBookingApi();
          final c = BookingWizardController(
            apiService: api,
            storage: MemoryBookingStateStorage(),
            recentLocationsStorage: RecentLocationsStorage(
              guestRepository: MemoryRecentLocationsRepository(),
            ),
            now: () => DateTime(2026, 12, 1),
          );
          c.markInitializedForTest();
          await c.applyRoutePrefill(
            serviceType: BookingServiceType.airportPickup,
            origin: const LocationOption(
              id: 'airport:BKK',
              displayName: 'BKK',
              kind: LocationKind.airport,
              code: 'BKK',
              latitude: 13.69,
              longitude: 100.75,
            ),
            destination: const LocationOption(
              id: 'qa-hotel',
              displayName: 'QA Hotel',
              kind: LocationKind.place,
              code: 'PATTAYA',
              latitude: 12.94,
              longitude: 100.89,
            ),
            initialStep: 1,
          );
          await c.setPickupDateTime(DateTime(2026, 12, 10, 10, 30));
          await c.goToStep(2);
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => LocaleState(),
              child: MaterialApp(
                locale: AppLocalizations.flutterLocale(locale),
                supportedLocales: [AppLocalizations.flutterLocale(locale)],
                localizationsDelegates: [
                  AppLocalizationsDelegate(locale),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: BookingWizardPage(controller: c),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations(locale);
          final sign = find.widgetWithText(SwitchListTile, l10n.t('name_sign'));
          final female = find.widgetWithText(
            SwitchListTile,
            l10n.t('booking_prefer_female_driver'),
          );
          expect(sign, findsOneWidget);
          expect(female, findsOneWidget);
          await tester.ensureVisible(sign);
          await tester.tap(sign);
          await tester.pumpAndSettle();
          expect(c.state.nameSign, isTrue);
          if (!unavailable)
            expect(
              (api.lastPricingRequest!['options'] as Map)['nameSign'],
              isTrue,
            );
          await tester.ensureVisible(female);
          await tester.tap(female);
          await tester.pumpAndSettle();
          expect(c.state.preferFemaleDriver, isTrue);
          expect(c.state.nameSign, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
