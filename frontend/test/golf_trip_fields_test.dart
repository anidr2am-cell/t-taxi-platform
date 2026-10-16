import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/golf_trip_fields.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'support/booking_wizard_test_helpers.dart';

final courses = [
  {
    'id': 1,
    'name': 'Phoenix Gold',
    'names': {'ko': '피닉스', 'th': 'ฟีนิกซ์ โกลด์', 'en': 'Phoenix Gold'},
    'lat': 12.819615,
    'lng': 100.952397,
  },
];
Widget wrap(Widget child, String lang) => MaterialApp(
  locale: Locale(lang),
  supportedLocales: const [
    Locale('ko'),
    Locale('en'),
    Locale('th'),
    Locale('ja'),
    Locale('zh'),
  ],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  test(
    'golf requires explicit choices and keeps hotel when switching outbound/return',
    () async {
      final storage = MemoryBookingStateStorage();
      final controller = BookingWizardController(
        apiService: CapturingBookingApi(),
        storage: storage,
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 10, 16),
      );
      await controller.initialize();
      await controller.selectService(BookingServiceType.golfTransfer);
      const hotel = LocationOption(
        id: 'sn',
        displayName: 'SN Plus',
        kind: LocationKind.place,
        code: 'PATTAYA',
        latitude: 12.9477908,
        longitude: 100.8968352,
      );
      await controller.setOrigin(hotel);
      expect(controller.canProceedFromStep(0), false);
      await controller.selectGolfCourse({
        'courseId': 1,
        'tripType': 'ROUND_TRIP',
        'holes': 18,
      }, courses.first);
      expect(controller.canProceedFromStep(0), true);
      expect(controller.state.destination!.kind, LocationKind.golf);
      await controller.selectGolfCourse({
        'courseId': 1,
        'tripType': 'RETURN',
      }, courses.first);
      expect(controller.state.origin!.kind, LocationKind.golf);
      expect(controller.state.destination!.id, 'sn');
      expect(controller.canProceedFromStep(0), true);
      expect(storage.value!.golf!['tripType'], 'RETURN');
      controller.dispose();
    },
  );
  test('golf choices survive draft persistence', () {
    const s = BookingWizardState(
      serviceType: BookingServiceType.golfTransfer,
      golf: {'courseId': 1, 'tripType': 'ROUND_TRIP', 'holes': 27},
    );
    expect(BookingWizardState.fromJson(s.toJson()).golf, s.golf);
    expect(s.copyWith(pickupTime: '14:00').golf, s.golf);
  });
  for (final lang in ['ko', 'en', 'th', 'ja', 'zh'])
    testWidgets('golf fields wrap at 375 in $lang; one way hides holes', (
      t,
    ) async {
      t.view.physicalSize = const Size(375, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Map<String, dynamic> value = {
        'courseId': 1,
        'tripType': 'ROUND_TRIP',
        'holes': 18,
      };
      await t.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (context, set) => GolfTripFields(
              value: value,
              courses: courses,
              onChanged: (v, c) => set(() => value = v),
            ),
          ),
          lang,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('golfHoles')), findsOneWidget);
      expect(
        find.text(AppLocalizations(lang).t('golf_package_included')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('golfTripType')));
      await t.pumpAndSettle();
      await t.tap(find.text(AppLocalizations(lang).t('golf_trip_RETURN')).last);
      await t.pumpAndSettle();
      expect(value['tripType'], 'RETURN');
      expect(find.byKey(const Key('golfHoles')), findsNothing);
      expect(t.takeException(), isNull);
    });
}
