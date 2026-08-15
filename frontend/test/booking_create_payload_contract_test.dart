import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';

import 'support/booking_wizard_test_helpers.dart';

void main() {
  test(
    'buildCreatePayload preserves full airport pickup create contract fields',
    () async {
      final controller = await buildContractAirportPickupController();

      final payload = controller.buildCreatePayload();

      expect(payload['bookingMode'], 'STANDARD');
      expect(payload['serviceTypeCode'], 'AIRPORT_PICKUP');
      expect(payload['vehicleTypeCode'], 'SUV');
      expect(payload['vehicleCount'], 1);
      expect(payload['scheduledPickupAt'], '2026-07-01T09:30:00+07:00');

      final origin = Map<String, dynamic>.from(payload['origin'] as Map);
      expect(origin['address'], 'Suvarnabhumi Airport, Thailand');
      expect(origin['placeId'], 'google-BKK');
      expect(origin['lat'], 13.6900);
      expect(origin['lng'], 100.7501);
      expect(origin['name'], 'Suvarnabhumi Airport');

      final destination = Map<String, dynamic>.from(
        payload['destination'] as Map,
      );
      expect(destination['address'], 'Pattaya, Chon Buri, Thailand');
      expect(destination['placeId'], 'google-pattaya');
      expect(destination['lat'], 12.9236);
      expect(destination['lng'], 100.8825);
      expect(destination['name'], 'Pattaya');

      expect(payload['originAirportIata'], 'BKK');
      expect(payload.containsKey('originLocationCode'), isFalse);
      expect(payload['destinationLocationCode'], 'PATTAYA');
      expect(payload.containsKey('destinationRegion'), isFalse);

      expect(payload['passengers'], {'adults': 2, 'children': 1, 'infants': 0});
      expect(payload['luggage'], {
        'carriers20Inch': 1,
        'carriers24InchPlus': 2,
        'golfBags': 1,
        'specialLuggageCount': 1,
      });
      expect(payload['options'], {
        'nameSign': true,
        'nameSignText': 'KIM FAMILY',
      });

      final transfer = Map<String, dynamic>.from(payload['transfer'] as Map);
      expect(transfer['airportIata'], 'BKK');
      expect(transfer['flightNumber'], 'TG409');

      final customer = Map<String, dynamic>.from(payload['customer'] as Map);
      expect(customer['name'], 'Kim Test');
      expect(customer['phone'], '+66123456789');
      expect(customer.containsKey('messengerType'), isFalse);
      expect(customer.containsKey('messengerId'), isFalse);
      expect(customer.containsKey('email'), isFalse);
      expect(customer.containsKey('countryCode'), isFalse);

      expect(payload['additionalRequests'], 'Need child seat');
      expect(payload.containsKey('totalAmount'), isFalse);
    },
  );

  test(
    'DMK airport pickup pricing request preserves DMK IATA contract field',
    () async {
      final api = CapturingBookingApi();
      final controller = await buildContractAirportPickupController(
        api: api,
        airportCode: 'DMK',
        airportName: 'Don Mueang Airport',
      );

      await controller.loadPricing();

      final body = api.lastPricingRequest!;
      expect(body['serviceTypeCode'], 'AIRPORT_PICKUP');
      expect(body['originAirportIata'], 'DMK');
      expect(body['destinationLocationCode'], 'PATTAYA');
      expect(body['passengers'], {'adults': 2, 'children': 1, 'infants': 0});
      expect(body['luggage'], {
        'carriers20Inch': 1,
        'carriers24InchPlus': 2,
        'golfBags': 1,
        'specialLuggageCount': 1,
      });
      expect(body['options'], {'nameSign': true});
    },
  );

  test(
    'city transfer pricing request preserves Bangkok and Pattaya location codes',
    () async {
      final api = CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'city:bangkok',
          displayName: 'Bangkok',
          kind: LocationKind.city,
          code: 'BANGKOK',
          name: 'Bangkok',
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'city:pattaya',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
          name: 'Pattaya',
          address: 'Pattaya, Thailand',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.loadPricing();

      final body = api.lastPricingRequest!;
      expect(body['originLocationCode'], 'BANGKOK');
      expect(body['destinationLocationCode'], 'PATTAYA');
      expect(body.containsKey('originAirportIata'), isFalse);
      expect(body.containsKey('destinationRegion'), isFalse);
    },
  );
}
