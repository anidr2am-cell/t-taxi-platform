import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/utils/booking_contact_preference.dart';
import 'package:frontend/features/booking/utils/customer_booking_format.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/services/places_api_service.dart';
import 'package:frontend/features/booking/widgets/google_places_search_field.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/booking_wizard_test_helpers.dart';

class _Memory extends BookingStateStorage {
  BookingWizardState? value;
  @override
  Future<void> save(BookingWizardState state) async {
    value = state;
  }

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<BookingWizardState?> load() async => value;
}

class _NoRecents implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption value) async {}
  @override
  Future<List<LocationOption>> load() async => [];
}

void main() {
  test(
    'new booking guidance is localized in every supported booking language',
    () {
      for (final language in ['ko', 'en', 'th', 'ja', 'zh', 'zh-TW', 'ru']) {
        final l10n = AppLocalizations(language);
        for (final key in [
          'ux_schedule_method',
          'ux_flight_mode',
          'ux_manual_mode',
          'ux_manual_time_toggle',
          'ux_optional_info',
          'ux_contact_after',
          'ux_phone_example',
          'ux_phone_help',
          'ux_phone_invalid',
          'ux_route_updated',
          'ux_fare_pending',
          'ux_route_edit',
          'ux_calculating',
        ]) {
          expect(l10n.t(key), isNot(key), reason: '$language/$key');
          if (language != 'en')
            expect(
              l10n.t(key),
              isNot(AppLocalizations('en').t(key)),
              reason: '$language/$key',
            );
        }
      }
      expect(AppLocalizations('zh-TW').t('ux_manual_mode'), contains('輸入'));
      expect(
        AppLocalizations('zh-TW').t('ux_manual_mode'),
        isNot(contains('输入')),
      );
    },
  );
  test(
    'country metadata keeps Italian zero, normalizes prefixes and rejects mismatches',
    () {
      for (final c in [
        ['+82', '010-1234-5678', '+821012345678'],
        ['+82', '82 10 1234 5678', '+821012345678'],
        ['+82', '+82 10 1234 5678', '+821012345678'],
        ['', '+66 81 234 5678', '+66812345678'],
        ['+82', '+44 7700 900123', '+447700900123'],
        ['+66', '081 234 5678', '+66812345678'],
        ['+81', '090-1234-5678', '+819012345678'],
        ['+1', '202-555-0123', '+12025550123'],
        ['+44', '07700 900123', '+447700900123'],
        ['+39', '06 1234 5678', '+390612345678'],
        ['+7', '8 (916) 123-45-67', '+79161234567'],
      ]) {
        expect(
          BookingContactPreference.normalizeBookingPhone(c[0], c[1]),
          c[2],
          reason: c[0] + '/' + c[1],
        );
      }
      expect(
        BookingContactPreference.normalizeBookingPhone(
          '+82',
          '+44 7700 900123',
        ),
        '+447700900123',
      );
      expect(BookingContactPreference.normalizeBookingPhone('+1', '123'), '');
      expect(
        BookingContactPreference.normalizeBookingPhone('+39', '06abc12345678'),
        '',
      );
    },
  );
  test(
    'Thai 24h display converts UTC midnight without changing +07 wall time',
    () {
      final ko = AppLocalizations('ko');
      for (final raw in ['2026-12-10T18:30:00Z', '2026-12-11T01:30:00+07:00'])
        expect(
          CustomerBookingFormat.pickupDateTime(ko, raw),
          '2026년 12월 11일 01:30 · 태국 시간',
        );
      expect(
        CustomerBookingFormat.pickupDate(ko, '2026-12-11', '22:10'),
        '2026년 12월 11일 22:10 · 태국 시간',
      );
    },
  );
  test(
    'schedule entry, editing invalidation and invalid manual input preserve other fields',
    () async {
      final c = BookingWizardController(
        storage: _Memory(),
        apiService: CapturingBookingApi(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _NoRecents(),
        ),
        now: () => DateTime.parse('2026-12-01T10:00:00+07:00'),
      );
      const a = LocationOption(
            id: 'airport:BKK',
            displayName: 'BKK',
            kind: LocationKind.airport,
            code: 'BKK',
            latitude: 13.69,
            longitude: 100.75,
          ),
          b = LocationOption(
            id: 'hotel',
            displayName: 'QA Hotel',
            kind: LocationKind.place,
            code: 'PATTAYA',
            latitude: 12.94,
            longitude: 100.89,
          );
      await c.applyRoutePrefill(
        serviceType: BookingServiceType.airportPickup,
        origin: a,
        destination: b,
        initialStep: BookingWizardSteps.schedule,
      );
      expect(c.state.step, BookingWizardSteps.schedule);
      expect(c.state.pickupTime, isNull);
      await c.setPickupDate(DateTime(2026, 12, 11));
      await c.setPickupTime(hour24: 22, minute: 10);
      await c.updatePassengersAndLuggage(adults: 2, luggage20: 2, golfBags: 1);
      c.setPickupTimeInputValid(false);
      expect(c.canProceedFromStep(BookingWizardSteps.schedule), isFalse);
      c.setPickupTimeInputValid(true);
      await c.goToStep(0);
      await c.invalidateRouteLocation(origin: false);
      expect(c.state.destination, isNull);
      expect(c.state.pricing, isNull);
      expect(c.state.pickupTime, '22:10');
      expect(c.state.adults, 2);
      expect(c.state.luggage20, 2);
      expect(c.state.golfBags, 1);
      await c.setDestination(b);
      expect(c.canProceedFromStep(0), isTrue);
      expect(c.routeNeedsReview, isTrue);
      c.dispose();
    },
  );
  testWidgets(
    'old autocomplete and details responses cannot replace a newer query',
    (tester) async {
      final old = Completer<http.Response>(),
          latest = Completer<http.Response>(),
          details = Completer<http.Response>();
      LocationOption? selected;
      http.Response rows(String id) => http.Response(
        jsonEncode({
          'data': {
            'predictions': [
              {'placeId': id, 'mainText': id, 'secondaryText': 'QA'},
            ],
          },
        }),
        200,
      );
      final api = PlacesApiService.test(
        baseUrl: 'https://qa.invalid',
        client: MockClient((q) {
          if (q.url.path.endsWith('details')) return details.future;
          return q.url.queryParameters['input'] == 'Older hotel'
              ? old.future
              : latest.future;
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GooglePlacesSearchField(
              label: 'Search',
              languageCode: 'en',
              placesApi: api,
              recentLocationsStorage: RecentLocationsStorage(
                guestRepository: _NoRecents(),
              ),
              onSelected: (v) => selected = v,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Older hotel');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(TextField), 'New hotel');
      await tester.pump(const Duration(milliseconds: 350));
      latest.complete(rows('New hotel'));
      await tester.pump();
      await tester.pump();
      old.complete(rows('Older hotel'));
      await tester.pump();
      expect(find.text('Older hotel'), findsNothing);
      await tester.tap(find.text('New hotel').last);
      await tester.pump();
      expect(selected, isNull);
      await tester.enterText(find.byType(TextField), 'Edited');
      await tester.pump();
      details.complete(
        http.Response(
          jsonEncode({
            'data': {
              'placeId': 'new',
              'name': 'Stale details',
              'lat': 12.94,
              'lng': 100.89,
            },
          }),
          200,
        ),
      );
      await tester.pump();
      expect(selected, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    },
  );
}
