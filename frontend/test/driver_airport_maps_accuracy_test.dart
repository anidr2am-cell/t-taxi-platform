import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/booking/models/airport_shortcuts.dart';
import 'package:frontend/features/booking/models/thailand_registered_airports.dart';
import 'package:frontend/features/driver/driver_trip_contact.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';

void main() {
  group('ThailandRegisteredAirports master data', () {
    test('registered airports include IATA, Samut Prakan BKK address, coords', () {
      const expected = {
        'BKK': (13.689999, 100.747924),
        'DMK': (13.913260, 100.602010),
        'CNX': (18.7679959, 98.968563),
        'HKT': (8.105401, 98.306054),
      };

      for (final entry in expected.entries) {
        final airport = ThailandRegisteredAirports.byCode(entry.key)!;
        expect(airport.displayName, contains(entry.key));
        expect(airport.displayName.toLowerCase(), contains('airport'));
        expect(airport.latitude, entry.value.$1);
        expect(airport.longitude, entry.value.$2);
        expect(airport.placeId, isNull);
        expect(airport.address!.toLowerCase(), isNot(equals('bangkok, thailand')));
        expect(airport.latitude, inInclusiveRange(5.0, 21.0));
        expect(airport.longitude, inInclusiveRange(97.0, 106.0));
        expect(
          AirportShortcuts.all.any((item) => item.code == entry.key),
          isTrue,
        );
      }

      final bkk = ThailandRegisteredAirports.byCode('BKK')!;
      expect(bkk.address, contains('Samut Prakan'));
      expect(bkk.address!.toLowerCase(), isNot(contains('bangkok')));
      // Bangkok city center is roughly 13.7563, 100.5018
      expect((bkk.latitude! - 13.7563).abs(), greaterThan(0.04));
      expect((bkk.longitude! - 100.5018).abs(), greaterThan(0.15));
    });
  });

  group('DriverTripContact maps URL priority', () {
    test('uses coordinates when both latitude and longitude are valid', () {
      final uri = DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(
          name: 'Anywhere',
          address: 'Bangkok',
          latitude: 13.689999,
          longitude: 100.747924,
          placeId: 'should-be-ignored',
        ),
      );

      expect(uri!.queryParameters['query'], '13.689999,100.747924');
      expect(uri.queryParameters.containsKey('query_place_id'), false);
    });

    test('rejects 0,0 NaN and incomplete coordinate pairs', () {
      expect(
        DriverTripContact.googleMapsUriForLocation(
          const DriverBookingLocation(latitude: 0, longitude: 0),
        ),
        isNull,
      );
      expect(
        DriverTripContact.googleMapsUriForLocation(
          const DriverBookingLocation(
            latitude: double.nan,
            longitude: 100.747924,
          ),
        ),
        isNull,
      );
      expect(
        DriverTripContact.googleMapsUriForLocation(
          const DriverBookingLocation(latitude: 13.689999, address: 'Bangkok'),
        ),
        isNull,
      );
      expect(
        DriverTripContact.googleMapsUriForLocation(
          const DriverBookingLocation(longitude: 100.747924),
        ),
        isNull,
      );
    });

    test('uses place id only with a usable query label', () {
      final uri = DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(
          name: 'Hilton Pattaya',
          address: '333/101 Beach Road',
          placeId: 'google-hilton-pattaya',
        ),
      );

      expect(uri!.queryParameters['query_place_id'], 'google-hilton-pattaya');
      expect(uri.queryParameters['query'], contains('Hilton Pattaya'));
      expect(uri.queryParameters.containsKey('api'), isTrue);
    });

    test('place id alone without query label does not invent a maps URL', () {
      expect(
        DriverTripContact.googleMapsUriForLocation(
          const DriverBookingLocation(placeId: 'ChIJ-verified-place'),
        ),
        isNull,
      );
    });

    test('does not open maps for ambiguous city or IATA-only text alone', () {
      for (final value in [
        'Bangkok',
        'Bangkok, Thailand',
        'Chiang Mai',
        'Phuket',
        'Thailand',
        'BKK',
        'DMK',
        'CNX',
        'HKT',
      ]) {
        // IATA-only enriches to airport coordinates (not a text query).
        final uri = DriverTripContact.googleMapsUriForLocation(
          DriverBookingLocation(address: value),
        );
        if (['BKK', 'DMK', 'CNX', 'HKT'].contains(value)) {
          expect(uri, isNotNull);
          expect(uri!.queryParameters['query'], contains(','));
          expect(
            RegExp(r'^-?\d+(\.\d+)?,-?\d+(\.\d+)?$')
                .hasMatch(uri.queryParameters['query']!),
            isTrue,
          );
        } else {
          expect(uri, isNull, reason: value);
        }
      }
    });

    test('does not treat unrelated BKK Hotel text as Suvarnabhumi', () {
      final uri = DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(
          name: 'BKK Hotel',
          address: 'Sukhumvit Road, Bangkok',
        ),
      );
      expect(uri!.queryParameters['query'], isNot(contains('13.689999')));
      expect(uri.queryParameters['query'], contains('BKK Hotel'));
    });

    test('legacy BKK booking with city address uses airport coordinates', () {
      final uri = DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(
          name: 'Suvarnabhumi Airport',
          address: 'Bangkok, Thailand',
        ),
      );

      expect(uri!.queryParameters['query'], '13.689999,100.747924');
    });

    test('DMK/CNX/HKT display labels include IATA and airport name', () {
      for (final code in ['BKK', 'DMK', 'CNX', 'HKT']) {
        final airport = ThailandRegisteredAirports.byCode(code)!;
        final label = DriverTripContact.displayLabelFor(
          DriverBookingLocation(
            name: airport.name,
            address: airport.address,
          ),
        );
        expect(label, contains(code));
        expect(label.toLowerCase(), contains('airport'));
      }
    });

    test('falls back to precise address when no coords/place id/airport', () {
      final uri = DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(
          name: 'Central Festival Pattaya Beach',
          address: '74/100 Moo 5, Pattaya City',
        ),
      );

      expect(
        uri!.queryParameters['query'],
        'Central Festival Pattaya Beach 74/100 Moo 5, Pattaya City',
      );
    });
  });
}
