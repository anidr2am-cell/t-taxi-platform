import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/place_prediction.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/places_api_service.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/widgets/step_vehicle_select.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'calculatePricing sends contract body with passengers, luggage, and options',
    () async {
      Uri? requestedUri;
      Map<String, dynamic>? body;
      final api = BookingApiService.test(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          requestedUri = request.url;
          body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'currency': 'THB', 'chargeItems': [], 'totalAmount': 0},
            }),
            200,
          );
        }),
      );

      await api.calculatePricing(
        serviceTypeCode: 'CITY_TRANSFER',
        vehicleTypeCode: 'SUV',
        scheduledPickupAt: '2026-07-01T09:30:00+07:00',
        originLocationCode: 'BANGKOK',
        destinationRegion: 'Pattaya',
        nameSign: true,
        adults: 2,
        children: 1,
        infants: 0,
        luggage20: 1,
        luggage24: 2,
        golfBags: 0,
        specialLuggageCount: 1,
      );

      expect(requestedUri!.path, '/api/v1/bookings/pricing/calculate');
      expect(body!['serviceTypeCode'], 'CITY_TRANSFER');
      expect(body!['vehicleTypeCode'], 'SUV');
      expect(body!['scheduledPickupAt'], '2026-07-01T09:30:00+07:00');
      expect(body!['originLocationCode'], 'BANGKOK');
      expect(body!['destinationRegion'], 'Pattaya');
      expect(body!['passengers'], {'adults': 2, 'children': 1, 'infants': 0});
      expect(body!['luggage'], {
        'carriers20Inch': 1,
        'carriers24InchPlus': 2,
        'golfBags': 0,
        'specialLuggageCount': 1,
      });
      expect(body!['options'], {'nameSign': true});
      expect(body!.containsKey('chargeOptions'), false);
    },
  );

  test(
    'createBooking serializes DateTime scheduledPickupAt to ISO string with Bangkok offset',
    () async {
      Map<String, dynamic>? body;
      final api = BookingApiService.test(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'bookingNumber': 'TX202607010001',
                'status': 'PENDING',
                'paymentMethod': 'PAY_DRIVER',
                'paymentStatus': 'UNPAID',
                'totalAmount': 0,
                'currency': 'THB',
              },
            }),
            201,
          );
        }),
      );

      await api.createBooking({
        'serviceTypeCode': 'CITY_TRANSFER',
        'vehicleTypeCode': 'SUV',
        'scheduledPickupAt': DateTime.parse('2026-07-01T09:30:00+07:00'),
      });

      expect(body!['scheduledPickupAt'], '2026-07-01T09:30:00+07:00');
      expect(body!['scheduledPickupAt'], isA<String>());
    },
  );

  test('createBooking preserves structured validation errors', () async {
    final api = BookingApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'Validation failed',
            'error_code': 'VALIDATION_ERROR',
            'errors': [
              {
                'source': 'body',
                'field': 'customer.name',
                'type': 'string.empty',
                'message': 'customer.name is required',
              },
            ],
          }),
          400,
        );
      }),
    );

    await expectLater(
      api.createBooking({
        'serviceTypeCode': 'CITY_TRANSFER',
        'vehicleTypeCode': 'SUV',
        'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
      }),
      throwsA(
        isA<BookingApiException>()
            .having((e) => e.errorCode, 'errorCode', 'VALIDATION_ERROR')
            .having((e) => e.errors.first.field, 'field', 'customer.name')
            .having((e) => e.errors.first.type, 'type', 'string.empty'),
      ),
    );
  });

  test(
    'createBooking preserves intended Bangkok wall time for local DateTime input',
    () async {
      Map<String, dynamic>? body;
      final api = BookingApiService.test(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'bookingNumber': 'TX202607010002'},
            }),
            201,
          );
        }),
      );

      await api.createBooking({
        'serviceTypeCode': 'CITY_TRANSFER',
        'vehicleTypeCode': 'SUV',
        'scheduledPickupAt': DateTime(2026, 7, 1, 9, 30),
      });

      expect(body!['scheduledPickupAt'], '2026-07-01T09:30:00+07:00');
    },
  );

  test(
    'createBooking rejects null or missing scheduledPickupAt before request submission',
    () async {
      var calls = 0;
      final api = BookingApiService.test(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          calls += 1;
          return http.Response('{}', 500);
        }),
      );

      await expectLater(
        api.createBooking({'scheduledPickupAt': null}),
        throwsA(isA<BookingApiException>()),
      );
      await expectLater(
        api.createBooking({'serviceTypeCode': 'CITY_TRANSFER'}),
        throwsA(isA<BookingApiException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'wizard pricing maps Google airport place and Pattaya to MVP pricing codes',
    () async {
      final api = _CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(
        const LocationOption(
          id: 'place:bkk',
          displayName: 'Suvarnabhumi Airport, Bangkok, Thailand',
          kind: LocationKind.place,
          placeId: 'google-bkk',
          name: 'Suvarnabhumi Airport',
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'place:pattaya',
          displayName: '파타야',
          kind: LocationKind.place,
          code: 'PATTAYA',
          placeId: 'google-pattaya',
          name: '파타야',
          address: '파타야 촌 부리 태국',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(
        adults: 2,
        luggage20: 1,
        luggage24: 2,
        nameSign: true,
      );
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');

      final body = api.lastPricingRequest!;
      expect(body['serviceTypeCode'], 'AIRPORT_PICKUP');
      expect(body['vehicleTypeCode'], 'SUV');
      expect(body['scheduledPickupAt'], '2026-07-01T09:30:00+07:00');
      expect(body['originAirportIata'], 'BKK');
      expect(body.containsKey('originLocationCode'), false);
      expect(body['destinationLocationCode'], 'PATTAYA');
      expect(body.containsKey('destinationRegion'), false);
      expect(body['passengers'], {'adults': 2, 'children': 0, 'infants': 0});
      expect(body['luggage'], {
        'carriers20Inch': 1,
        'carriers24InchPlus': 2,
        'golfBags': 0,
        'specialLuggageCount': 0,
      });
      expect(body['options'], {'nameSign': true});
    },
  );

  test(
    'airport dropoff pricing request uses Pattaya origin and BKK destination codes',
    () async {
      final api = _CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.selectService(BookingServiceType.airportDropoff);
      await controller.setOrigin(
        const LocationOption(
          id: 'place:pattaya',
          displayName: '파타야',
          kind: LocationKind.place,
          code: 'PATTAYA',
          placeId: 'google-pattaya',
          name: '파타야',
          address: '파타야 촌 부리 태국',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'bkk',
          displayName: 'Suvarnabhumi Airport',
          kind: LocationKind.airport,
          code: 'BKK',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');

      final body = api.lastPricingRequest!;
      expect(body['serviceTypeCode'], 'AIRPORT_DROPOFF');
      expect(body['vehicleTypeCode'], 'SUV');
      expect(body['originLocationCode'], 'PATTAYA');
      expect(body['destinationLocationCode'], 'BKK');
      expect(body.containsKey('originAirportIata'), false);
      expect(body.containsKey('destinationRegion'), false);
    },
  );

  test(
    'airport pickup create payload includes flight number in transfer',
    () async {
      final controller = BookingWizardController(
        apiService: _CapturingBookingApi(),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(
        const LocationOption(
          id: 'bkk',
          displayName: 'Suvarnabhumi Airport',
          kind: LocationKind.airport,
          code: 'BKK',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'pattaya',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updateCustomerInfo(flightNumber: '7c-2203');
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');

      final payload = controller.buildCreatePayload();

      expect(payload['transfer'], isA<Map>());
      expect(payload['transfer']['flightNumber'], '7C2203');
    },
  );

  test(
    'airport pickup create payload includes nameSignText only when name sign is selected',
    () async {
      final controller = BookingWizardController(
        apiService: _CapturingBookingApi(),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(
        const LocationOption(
          id: 'bkk',
          displayName: 'Suvarnabhumi Airport',
          kind: LocationKind.airport,
          code: 'BKK',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'pattaya',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(
        adults: 2,
        nameSign: true,
        nameSignText: '  KIM FAMILY  ',
      );
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');

      final payload = controller.buildCreatePayload();
      expect(payload['options'], {
        'nameSign': true,
        'nameSignText': 'KIM FAMILY',
        'preferFemaleDriver': false,
      });

      await controller.updatePassengersAndLuggage(nameSign: false);
      final disabledPayload = controller.buildCreatePayload();
      expect(disabledPayload['options'], {
        'nameSign': false,
        'preferFemaleDriver': false,
      });
    },
  );

  test('non-airport-pickup create payload omits stale flight number', () async {
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.selectService(BookingServiceType.cityTransfer);
    await controller.setOrigin(
      const LocationOption(
        id: 'origin',
        displayName: 'Bangkok',
        kind: LocationKind.city,
        code: 'BANGKOK',
      ),
    );
    await controller.setDestination(
      const LocationOption(
        id: 'destination',
        displayName: 'Pattaya',
        kind: LocationKind.city,
        code: 'PATTAYA',
      ),
    );
    await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
    await controller.updateCustomerInfo(flightNumber: '7C2203');
    await controller.updatePassengersAndLuggage(adults: 2);
    await controller.loadRecommendation();
    await controller.selectVehicle('SUV');

    final payload = controller.buildCreatePayload();

    expect(payload.containsKey('transfer'), false);
  });

  test('service change clears stale flight number from wizard state', () async {
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
    );

    await controller.selectService(BookingServiceType.airportPickup);
    await controller.updateCustomerInfo(flightNumber: '7C2203');
    await controller.selectService(BookingServiceType.cityTransfer);

    expect(controller.state.flightNumber, '');
  });

  test(
    'place details keep localized display text while storing MVP internal code',
    () {
      final location = LocationOption.fromPlaceDetails(
        const PlaceDetails(
          placeId: 'google-pattaya',
          name: '파타야',
          address: '파타야 촌 부리 태국',
        ),
      );

      expect(location.displayName, '파타야');
      expect(location.name, '파타야');
      expect(location.address, '파타야 촌 부리 태국');
      expect(location.code, 'PATTAYA');
      expect(location.placeId, 'google-pattaya');
    },
  );

  test(
    'place details map Pattaya local-language variants to internal route code',
    () {
      for (final details in const [
        PlaceDetails(
          placeId: 'google-pattaya-th',
          name: 'เมืองพัทยา',
          address: 'อำเภอบางละมุง ชลบุรี ประเทศไทย',
        ),
        PlaceDetails(
          placeId: 'google-pattaya-ja',
          name: 'パタヤ',
          address: 'チョンブリー タイ',
        ),
        PlaceDetails(
          placeId: 'google-pattaya-zh',
          name: '芭堤雅',
          address: '春武里府 泰国',
        ),
      ]) {
        final location = LocationOption.fromPlaceDetails(details);
        expect(location.code, 'PATTAYA');
      }
    },
  );

  test('pickup date cannot be in the past', () async {
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    final ok = await controller.setPickupDateTime(DateTime(2026, 6, 28, 12));

    expect(ok, false);
    expect(controller.state.errorMessage, contains('past'));
  });

  test('pickup within two hours is allowed as urgent window', () {
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    expect(
      controller.isUrgentPickupWindow(DateTime(2026, 6, 29, 11, 30)),
      isTrue,
    );
    expect(
      controller.isStandardPickupAllowed(DateTime(2026, 6, 29, 11, 30)),
      isFalse,
    );
  });

  test('pickup date and time persist in wizard state', () async {
    final storage = _MemoryBookingStateStorage();
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: storage,
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
    final restored = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: storage,
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );
    await restored.initialize();

    expect(restored.state.pickupDate, '2026-07-01');
    expect(restored.state.pickupTime, '09:30');
    expect(restored.scheduledPickupAtIso(), '2026-07-01T09:30:00+07:00');
  });

  test('initialize reseeds past stored pickup to defaultPickupDateTime', () async {
    final storage = _MemoryBookingStateStorage()
      ..value = const BookingWizardState(
        pickupDate: '2026-06-01',
        pickupTime: '09:30',
      );
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: storage,
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.initialize();

    final defaultPickup = controller.defaultPickupDateTime();
    expect(controller.state.pickupDate, controller.formatDate(defaultPickup));
    expect(controller.state.pickupTime, controller.formatTime(defaultPickup));
    expect(storage.value?.pickupDate, controller.state.pickupDate);
    expect(storage.value?.pickupTime, controller.state.pickupTime);
  });

  test('initialize seeds default pickup when storage is empty', () async {
    final storage = _MemoryBookingStateStorage();
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: storage,
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.initialize();

    final defaultPickup = controller.defaultPickupDateTime();
    expect(controller.state.pickupDate, controller.formatDate(defaultPickup));
    expect(controller.state.pickupTime, controller.formatTime(defaultPickup));
  });

  test('reset reseeds default pickup after clearing storage', () async {
    final storage = _MemoryBookingStateStorage()
      ..value = const BookingWizardState(
        pickupDate: '2026-06-01',
        pickupTime: '09:30',
        serviceType: BookingServiceType.cityTransfer,
      );
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: storage,
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.reset();

    expect(controller.state.serviceType, isNull);
    final defaultPickup = controller.defaultPickupDateTime();
    expect(controller.state.pickupDate, controller.formatDate(defaultPickup));
    expect(controller.state.pickupTime, controller.formatTime(defaultPickup));
    expect(storage.value?.pickupDate, controller.state.pickupDate);
  });

  test(
    'restored localized pickup time is normalized for recommendation validation',
    () async {
      final storage = _MemoryBookingStateStorage()
        ..value = const BookingWizardState(
          serviceType: BookingServiceType.airportPickup,
          origin: LocationOption(
            id: 'bkk',
            displayName: 'Suvarnabhumi Airport',
            kind: LocationKind.airport,
            code: 'BKK',
          ),
          destination: LocationOption(
            id: 'pattaya',
            displayName: '파타야',
            kind: LocationKind.place,
            code: 'PATTAYA',
            placeId: 'google-pattaya',
            name: '파타야',
            address: '파타야 촌 부리 태국',
          ),
          pickupDate: '2026-07-08',
          pickupTime: '12:04 오전',
          adults: 2,
        );
      final controller = BookingWizardController(
        apiService: _CapturingBookingApi(),
        storage: storage,
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 7, 7, 10),
      );

      await controller.initialize();

      expect(controller.state.pickupTime, '00:04');
      expect(controller.selectedPickupDateTime(), DateTime(2026, 7, 8, 0, 4));
      expect(controller.canLoadRecommendation(), true);
      expect(controller.state.recommendation, isNotNull);
      expect(controller.state.selectedVehicle, 'SUV');
      expect(controller.state.pricing, isNotNull);
      expect(controller.stepValidationMessageKey(2), isNull);
    },
  );

  test('booking payload includes scheduledPickupAt ISO-8601 field', () async {
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.selectService(BookingServiceType.cityTransfer);
    await controller.setOrigin(
      const LocationOption(
        id: 'origin',
        displayName: 'Bangkok',
        kind: LocationKind.city,
        code: 'BANGKOK',
      ),
    );
    await controller.setDestination(
      const LocationOption(
        id: 'destination',
        displayName: 'Pattaya',
        kind: LocationKind.city,
        code: 'PATTAYA',
      ),
    );
    await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
    await controller.updatePassengersAndLuggage(adults: 2);
    await controller.loadRecommendation();
    await controller.selectVehicle('SUV');
    await controller.updateCustomerInfo(
      name: 'Kim',
      phone: '+66123456789',
    );

    final payload = controller.buildCreatePayload();

    expect(payload['scheduledPickupAt'], '2026-07-01T09:30:00+07:00');
    expect(payload['scheduledPickupAt'], isA<String>());
  });

  test(
    'map-selected locations retain address and coordinates in payload',
    () async {
      final controller = BookingWizardController(
        apiService: _CapturingBookingApi(),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );
      final origin = LocationOption.fromCoordinates(
        latitude: 13.6900,
        longitude: 100.7501,
        address: 'Suvarnabhumi Airport, Bangkok, Thailand',
      );
      final destination = LocationOption.fromCoordinates(
        latitude: 12.9236,
        longitude: 100.8825,
        address: 'เมืองพัทยา จังหวัดชลบุรี ประเทศไทย',
      );

      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(origin);
      await controller.setDestination(destination);
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'Kim',
        phone: '+66123456789',
      );

      final payload = controller.buildCreatePayload();
      final customer = Map<String, dynamic>.from(payload['customer'] as Map);
      final originPayload = Map<String, dynamic>.from(payload['origin'] as Map);
      final destinationPayload = Map<String, dynamic>.from(
        payload['destination'] as Map,
      );

      expect(customer['name'], 'Kim');
      expect(customer['phone'], '+66123456789');
      expect(customer.containsKey('messengerType'), isFalse);
      expect(customer.containsKey('messengerId'), isFalse);
      expect(customer.containsKey('email'), isFalse);
      expect(customer.containsKey('countryCode'), isFalse);
      expect(origin.code, 'BKK');
      expect(destination.code, 'PATTAYA');
      expect(originPayload, containsPair('address', origin.address));
      expect(originPayload, containsPair('lat', 13.6900));
      expect(originPayload, containsPair('lng', 100.7501));
      expect(destinationPayload, containsPair('address', destination.address));
      expect(
        destinationPayload['address'],
        'เมืองพัทยา จังหวัดชลบุรี ประเทศไทย',
      );
      expect(destinationPayload, containsPair('lat', 12.9236));
      expect(destinationPayload, containsPair('lng', 100.8825));
      expect(controller.state.pricing, isNotNull);
    },
  );

  test('bookingPricingInquiryMessage maps route not found to inquiry key', () {
    final message = bookingPricingInquiryMessage(
      BookingApiException(
        'Route not found for the given service and locations',
        'NOT_FOUND',
      ),
    );
    expect(message, 'pricing_inquiry_required');
  });

  test(
    'bookingPricingInquiryMessage maps missing vehicle price to inquiry key',
    () {
      final message = bookingPricingInquiryMessage(
        BookingApiException(
          'Vehicle price not configured for this route',
          'NOT_FOUND',
        ),
      );
      expect(message, 'pricing_inquiry_required');
    },
  );

  test('bookingPricingInquiryMessage ignores unrelated errors', () {
    final message = bookingPricingInquiryMessage(
      BookingApiException('Validation failed', 'VALIDATION_ERROR'),
    );
    expect(message, isNull);
  });

  test('bookingPricingInquiryMessage maps INQUIRY_REQUIRED to inquiry key', () {
    final message = bookingPricingInquiryMessage(
      BookingApiException(
        'Pricing inquiry required for long distance',
        'INQUIRY_REQUIRED',
      ),
    );
    expect(message, 'pricing_inquiry_required');
  });

  test(
    'loadPricing maps INQUIRY_REQUIRED to pricing inquiry message',
    () async {
      final controller = BookingWizardController(
        apiService: _InquiryPricingApi(),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        LocationOption.fromCoordinates(
          latitude: 13.759,
          longitude: 100.4977,
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        LocationOption.fromCoordinates(
          latitude: 13.80,
          longitude: 100.5018,
          address: 'Nearby Hotel, Bangkok',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SEDAN');
      await controller.loadPricing();

      expect(controller.state.errorMessage, 'pricing_inquiry_required');
      expect(controller.state.pricing, isNull);
    },
  );

  test(
    'loadPricing sends coordinates for CITY_TRANSFER when locations have lat/lng',
    () async {
      final api = _CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        LocationOption.fromCoordinates(
          latitude: 13.759,
          longitude: 100.4977,
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        LocationOption.fromCoordinates(
          latitude: 12.9236,
          longitude: 100.8825,
          address: 'Solyn Hotel, Pattaya, Thailand',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SEDAN');
      await controller.loadPricing();

      expect(api.lastPricingRequest, isNotNull);
      expect(api.lastPricingRequest!['serviceTypeCode'], 'CITY_TRANSFER');
      expect(api.lastPricingRequest!['originLat'], 13.759);
      expect(api.lastPricingRequest!['originLng'], 100.4977);
      expect(api.lastPricingRequest!['destinationLat'], 12.9236);
      expect(api.lastPricingRequest!['destinationLng'], 100.8825);
    },
  );

  test(
    'loadPricing sends coordinates for CITY_TRANSFER place-search selections (Solyn ↔ Centric Sea)',
    () async {
      final api = _CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        LocationOption.fromPlaceDetails(
          const PlaceDetails(
            placeId: 'ChIJJciWWI6f4jARooYEqzN19NA',
            name: 'Solyn Hotel',
            address:
                '4969 Pracha Songkhro Rd, Din Daeng, Krung Thep Maha Nakhon, Thailand',
            latitude: 13.7730064,
            longitude: 100.5601678,
          ),
        ),
      );
      await controller.setDestination(
        LocationOption.fromPlaceDetails(
          const PlaceDetails(
            placeId: 'ChIJZVKZKQGWAjERHntnx3WtANQ',
            name: 'Centric Sea Pattaya',
            address: 'Pattaya Sai Song Road, Pattaya, Thailand',
            latitude: 12.9395321,
            longitude: 100.8883189,
          ),
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SEDAN');
      await controller.loadPricing();

      expect(api.lastPricingRequest, isNotNull);
      expect(api.lastPricingRequest!['originLocationCode'], 'Solyn Hotel');
      expect(api.lastPricingRequest!['destinationLocationCode'], 'PATTAYA');
      expect(api.lastPricingRequest!['originLat'], 13.7730064);
      expect(api.lastPricingRequest!['originLng'], 100.5601678);
      expect(api.lastPricingRequest!['destinationLat'], 12.9395321);
      expect(api.lastPricingRequest!['destinationLng'], 100.8883189);
    },
  );

  test(
    'loadPricing hydrates missing coordinates from placeId before CITY_TRANSFER pricing',
    () async {
      final api = _CapturingBookingApi();
      final placesApi = PlacesApiService.test(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          final uri = request.url;
          if (uri.path.endsWith('/places/details') &&
              uri.queryParameters['placeId'] == 'ChIJJciWWI6f4jARooYEqzN19NA') {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'placeId': 'ChIJJciWWI6f4jARooYEqzN19NA',
                  'name': 'Solyn Hotel',
                  'formattedAddress': 'Bangkok, Thailand',
                  'lat': 13.7730064,
                  'lng': 100.5601678,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (uri.path.endsWith('/places/details') &&
              uri.queryParameters['placeId'] == 'ChIJZVKZKQGWAjERHntnx3WtANQ') {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'placeId': 'ChIJZVKZKQGWAjERHntnx3WtANQ',
                  'name': 'Centric Sea Pattaya',
                  'formattedAddress': 'Pattaya, Thailand',
                  'lat': 12.9395321,
                  'lng': 100.8883189,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"success":false,"message":"not found"}', 404);
        }),
      );
      final controller = BookingWizardController(
        apiService: api,
        placesApiService: placesApi,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'place:ChIJJciWWI6f4jARooYEqzN19NA',
          displayName: 'Solyn Hotel',
          kind: LocationKind.place,
          placeId: 'ChIJJciWWI6f4jARooYEqzN19NA',
          name: 'Solyn Hotel',
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'place:ChIJZVKZKQGWAjERHntnx3WtANQ',
          displayName: 'Centric Sea Pattaya',
          kind: LocationKind.place,
          placeId: 'ChIJZVKZKQGWAjERHntnx3WtANQ',
          name: 'Centric Sea Pattaya',
          address: 'Pattaya, Thailand',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SEDAN');
      await controller.loadPricing();

      expect(api.lastPricingRequest!['originLat'], 13.7730064);
      expect(api.lastPricingRequest!['originLng'], 100.5601678);
      expect(api.lastPricingRequest!['destinationLat'], 12.9395321);
      expect(api.lastPricingRequest!['destinationLng'], 100.8883189);
      expect(controller.state.origin?.hasCoordinates, isTrue);
      expect(controller.state.destination?.hasCoordinates, isTrue);
    },
  );

  test(
    'loadPricing omits coordinates for AIRPORT_PICKUP even when places have lat/lng',
    () async {
      final api = _CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(
        LocationOption.fromPlaceDetails(
          const PlaceDetails(
            placeId: 'google-bkk',
            name: 'Suvarnabhumi Airport',
            address: 'Bang Phli, Samut Prakan, Thailand',
            latitude: 13.69,
            longitude: 100.7501,
          ),
        ),
      );
      await controller.setDestination(
        LocationOption.fromPlaceDetails(
          const PlaceDetails(
            placeId: 'google-pattaya',
            name: 'Pattaya',
            address: 'Pattaya, Chon Buri, Thailand',
            latitude: 12.9236,
            longitude: 100.8825,
          ),
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.loadPricing();

      expect(api.lastPricingRequest, isNotNull);
      expect(api.lastPricingRequest!['serviceTypeCode'], 'AIRPORT_PICKUP');
      expect(api.lastPricingRequest!.containsKey('originLat'), isFalse);
      expect(api.lastPricingRequest!.containsKey('destinationLat'), isFalse);
    },
  );

  test(
    'loadPricing keeps fixed-route location codes for CITY_TRANSFER with known region codes',
    () async {
      final api = _CapturingBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'origin',
          displayName: 'Bangkok',
          kind: LocationKind.city,
          code: 'BANGKOK',
          latitude: 13.7563,
          longitude: 100.5018,
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'destination',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
          latitude: 12.9236,
          longitude: 100.8825,
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.loadPricing();

      expect(api.lastPricingRequest!['originLocationCode'], 'BANGKOK');
      expect(api.lastPricingRequest!['destinationLocationCode'], 'PATTAYA');
      expect(api.lastPricingRequest!['originLat'], 13.7563);
      expect(api.lastPricingRequest!['destinationLat'], 12.9236);
    },
  );

  test(
    'submitBooking completes with distance-based pricing and place coordinates in payload',
    () async {
      final api = _SuccessfulCreateBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        LocationOption.fromCoordinates(
          latitude: 13.759,
          longitude: 100.4977,
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        LocationOption.fromCoordinates(
          latitude: 12.9236,
          longitude: 100.8825,
          address: 'Solyn Hotel, Pattaya, Thailand',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SEDAN');
      await controller.updateCustomerInfo(
        name: 'Kim',
        phone: '+66123456789',
      );

      final result = await controller.submitBooking();

      expect(result, isNotNull);
      expect(result!.totalAmount, 1300);
      expect(api.lastPricingRequest!['originLat'], 13.759);
      expect(api.lastPricingRequest!['destinationLat'], 12.9236);
      final destination = Map<String, dynamic>.from(
        api.lastCreateRequest!['destination'] as Map,
      );
      expect(destination['lat'], 12.9236);
      expect(destination['lng'], 100.8825);
    },
  );

  test(
    'submitBooking hydrates origin.lat/lng before CITY_TRANSFER create (Solyn -> Centric Sea)',
    () async {
      final api = _SuccessfulCreateBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        placesApiService: _solynCentricPlacesApi(),
        storage: _MemoryBookingStateStorage()
          ..value = _cityTransferSubmitReadyState(
            origin: _solynHotelWithoutCoords(),
            destination: _centricSeaWithoutCoords(),
          ),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.loadRecommendation();
      await controller.loadPricing();
      final result = await controller.submitBooking();

      expect(result, isNotNull);
      expect(api.lastCreateRequest, isNotNull);
      final origin = Map<String, dynamic>.from(
        api.lastCreateRequest!['origin'] as Map,
      );
      final destination = Map<String, dynamic>.from(
        api.lastCreateRequest!['destination'] as Map,
      );
      expect(origin['lat'], 13.7730064);
      expect(origin['lng'], 100.5601678);
      expect(destination['lat'], 12.9395321);
      expect(destination['lng'], 100.8883189);
    },
  );

  test(
    'submitBooking hydrates origin.lat/lng before CITY_TRANSFER create (Centric Sea -> Solyn)',
    () async {
      final api = _SuccessfulCreateBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        placesApiService: _solynCentricPlacesApi(),
        storage: _MemoryBookingStateStorage()
          ..value = _cityTransferSubmitReadyState(
            origin: _centricSeaWithoutCoords(),
            destination: _solynHotelWithoutCoords(),
          ),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.loadRecommendation();
      await controller.loadPricing();
      await controller.submitBooking();

      final origin = Map<String, dynamic>.from(
        api.lastCreateRequest!['origin'] as Map,
      );
      final destination = Map<String, dynamic>.from(
        api.lastCreateRequest!['destination'] as Map,
      );
      expect(origin['lat'], 12.9395321);
      expect(origin['lng'], 100.8883189);
      expect(destination['lat'], 13.7730064);
      expect(destination['lng'], 100.5601678);
    },
  );

  test(
    'submitBooking blocks CITY_TRANSFER create when coordinates cannot be resolved',
    () async {
      final api = _SuccessfulCreateBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage()
          ..value = _cityTransferSubmitReadyState(
            origin: const LocationOption(
              id: 'origin:custom',
              displayName: 'Custom origin',
              kind: LocationKind.place,
              name: 'Custom origin',
              address: 'Unknown street, Nonthaburi, Thailand',
            ),
            destination: const LocationOption(
              id: 'destination:custom',
              displayName: 'Custom destination',
              kind: LocationKind.place,
              name: 'Custom destination',
              address: 'Unknown road, Chiang Mai, Thailand',
            ),
          ),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.loadRecommendation();
      await controller.loadPricing();
      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(api.lastCreateRequest, isNull);
      expect(
        controller.state.errorMessage,
        'booking_location_reselect_required',
      );
    },
  );

  test(
    'submitBooking AIRPORT_PICKUP create payload keeps nested lat/lng without CITY_TRANSFER hydration',
    () async {
      final api = _SuccessfulCreateBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(
        LocationOption.fromPlaceDetails(
          const PlaceDetails(
            placeId: 'google-bkk',
            name: 'Suvarnabhumi Airport',
            address: 'Bang Phli, Samut Prakan, Thailand',
            latitude: 13.6900,
            longitude: 100.7501,
          ),
        ),
      );
      await controller.setDestination(
        LocationOption.fromPlaceDetails(
          const PlaceDetails(
            placeId: 'google-pattaya',
            name: 'Pattaya',
            address: 'Pattaya, Chon Buri, Thailand',
            latitude: 12.9236,
            longitude: 100.8825,
          ),
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'Kim',
        phone: '+66123456789',
      );

      final result = await controller.submitBooking();

      expect(result, isNotNull);
      expect(api.lastCreateRequest!['serviceTypeCode'], 'AIRPORT_PICKUP');
      final origin = Map<String, dynamic>.from(
        api.lastCreateRequest!['origin'] as Map,
      );
      expect(origin['lat'], 13.6900);
      expect(origin['lng'], 100.7501);
      expect(api.lastCreateRequest!.containsKey('originLat'), isFalse);
    },
  );

  testWidgets(
    'vehicle step shows customer-facing base price without km estimate text',
    (tester) async {
      final api = _SuccessfulCreateBookingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        LocationOption.fromCoordinates(
          latitude: 13.759,
          longitude: 100.4977,
          address: 'Bangkok, Thailand',
        ),
      );
      await controller.setDestination(
        LocationOption.fromCoordinates(
          latitude: 12.9236,
          longitude: 100.8825,
          address: 'Solyn Hotel, Pattaya, Thailand',
        ),
      );
      await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SEDAN');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => StepVehicleSelect(
                state: controller.state,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('km est'), findsNothing);
      expect(find.textContaining('132.34'), findsNothing);
      expect(find.text('Base price'), findsOneWidget);
      expect(find.textContaining('1300 THB'), findsAtLeastNWidgets(1));
    },
  );

  test(
    'booking create payload fails before submission when pickup time is missing',
    () async {
      final controller = BookingWizardController(
        apiService: _CapturingBookingApi(),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
      );

      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'origin',
          displayName: 'Bangkok',
          kind: LocationKind.city,
          code: 'BANGKOK',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'destination',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
        ),
      );
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'Kim',
        email: 'kim@example.com',
        phone: '+66123456789',
      );

      expect(controller.buildCreatePayload, throwsA(isA<StateError>()));
    },
  );

  test(
    'submit maps backend customer.name validation error to customer step',
    () async {
      final controller = BookingWizardController(
        apiService: _FailingCreateBookingApi(
          BookingApiException('Validation failed', 'VALIDATION_ERROR', [
            const BookingApiErrorDetail(
              source: 'body',
              field: 'customer.name',
              type: 'string.empty',
              message: 'customer.name is required',
            ),
          ]),
        ),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'origin',
          displayName: 'Bangkok',
          kind: LocationKind.city,
          code: 'BANGKOK',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'destination',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
        ),
      );
      await controller.setPickupDateTime(DateTime(2099, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'สมชาย ใจดี',
        phone: '+66123456789',
      );

      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(controller.state.step, 3);
      expect(controller.state.errorMessage, 'wizard_required_customer_name');
      expect(controller.state.errorMessage, isNot('Validation failed'));
    },
  );

  test(
    'submit maps backend transfer.flightNumber validation error to pickup step',
    () async {
      final controller = BookingWizardController(
        apiService: _FailingCreateBookingApi(
          BookingApiException('Validation failed', 'VALIDATION_ERROR', [
            const BookingApiErrorDetail(
              source: 'body',
              field: 'transfer.flightNumber',
              type: 'any.invalid',
              message: 'Invalid flight number format. Examples: TG401, 7C2203',
            ),
          ]),
        ),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
      );

      await controller.initialize();
      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(
        const LocationOption(
          id: 'bkk',
          displayName: 'Suvarnabhumi Airport',
          kind: LocationKind.airport,
          code: 'BKK',
        ),
      );
      await controller.setDestination(
        const LocationOption(
          id: 'pattaya',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
        ),
      );
      await controller.setPickupDateTime(DateTime(2099, 7, 1, 9, 30));
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'Kim',
        phone: '+66123456789',
        flightNumber: 'bad-flight',
      );

      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(controller.state.step, 1);
      expect(controller.state.errorMessage, 'flight_number_invalid');
      expect(controller.state.errorMessage, isNot('Validation failed'));
    },
  );

  test(
    'submit maps backend scheduledPickupAt validation error to pickup step',
    () async {
      final controller = BookingWizardController(
        apiService: _FailingCreateBookingApi(
          BookingApiException('Validation failed', 'VALIDATION_ERROR', [
            const BookingApiErrorDetail(
              source: 'body',
              field: 'scheduledPickupAt',
              type: 'any.custom',
              message: 'scheduledPickupAt must be at least 2 hours from now',
            ),
          ]),
        ),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
      );

      await _fillSubmittableCityTransfer(controller);

      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(controller.state.step, 1);
      expect(controller.state.errorMessage, 'pickup_datetime_required');
      expect(controller.state.errorMessage, isNot('Validation failed'));
    },
  );

  test(
    'submit maps backend passengers.adults validation error to passenger step',
    () async {
      final controller = BookingWizardController(
        apiService: _FailingCreateBookingApi(
          BookingApiException('Validation failed', 'VALIDATION_ERROR', [
            const BookingApiErrorDetail(
              source: 'body',
              field: 'passengers.adults',
              type: 'number.min',
              message: 'passengers.adults must be greater than or equal to 1',
            ),
          ]),
        ),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
      );

      await _fillSubmittableCityTransfer(controller);

      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(controller.state.step, 2);
      expect(controller.state.errorMessage, 'wizard_required_passengers');
      expect(controller.state.errorMessage, isNot('Validation failed'));
    },
  );
}

Future<void> _fillSubmittableCityTransfer(
  BookingWizardController controller,
) async {
  await controller.initialize();
  await controller.selectService(BookingServiceType.cityTransfer);
  await controller.setOrigin(
    const LocationOption(
      id: 'origin',
      displayName: 'Bangkok',
      kind: LocationKind.city,
      code: 'BANGKOK',
    ),
  );
  await controller.setDestination(
    const LocationOption(
      id: 'destination',
      displayName: 'Pattaya',
      kind: LocationKind.city,
      code: 'PATTAYA',
    ),
  );
  await controller.setPickupDateTime(DateTime(2099, 7, 1, 9, 30));
  await controller.updatePassengersAndLuggage(adults: 2);
  await controller.loadRecommendation();
  await controller.selectVehicle('SUV');
  await controller.updateCustomerInfo(
    name: 'Kim',
    phone: '+66123456789',
  );
}

class _CapturingBookingApi implements BookingApiService {
  Map<String, dynamic>? lastPricingRequest;

  @override
  Future<VehicleRecommendation> recommendVehicle({
    required int adults,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) async {
    return const VehicleRecommendation(
      recommendedVehicle: 'SUV',
      selectableVehicles: ['SUV', 'VAN'],
      multipleVehicles: false,
      message: 'OK',
    );
  }

  @override
  Future<PricingResult> calculatePricing({
    required String serviceTypeCode,
    required String vehicleTypeCode,
    int vehicleCount = 1,
    String? originAirportIata,
    String? destinationRegion,
    String? originLocationCode,
    String? destinationLocationCode,
    bool nameSign = false,
    String? scheduledPickupAt,
    int adults = 1,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
  }) async {
    final request = <String, dynamic>{
      'serviceTypeCode': serviceTypeCode,
      'vehicleTypeCode': vehicleTypeCode,
      'vehicleCount': vehicleCount,
      'passengers': {
        'adults': adults,
        'children': children,
        'infants': infants,
      },
      'luggage': {
        'carriers20Inch': luggage20,
        'carriers24InchPlus': luggage24,
        'golfBags': golfBags,
        'specialLuggageCount': specialLuggageCount,
      },
      'options': {'nameSign': nameSign},
    };
    if (originAirportIata != null) {
      request['originAirportIata'] = originAirportIata;
    }
    if (destinationRegion != null) {
      request['destinationRegion'] = destinationRegion;
    }
    if (originLocationCode != null) {
      request['originLocationCode'] = originLocationCode;
    }
    if (destinationLocationCode != null) {
      request['destinationLocationCode'] = destinationLocationCode;
    }
    if (scheduledPickupAt != null) {
      request['scheduledPickupAt'] = scheduledPickupAt;
    }
    if (originLat != null) request['originLat'] = originLat;
    if (originLng != null) request['originLng'] = originLng;
    if (destinationLat != null) request['destinationLat'] = destinationLat;
    if (destinationLng != null) request['destinationLng'] = destinationLng;
    lastPricingRequest = request;
    return const PricingResult(
      currency: 'THB',
      chargeItems: [],
      totalAmount: 0,
    );
  }

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
    String? accessToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DropoffQrIssueResult> issueDropoffQr({
    required String bookingNumber,
    required String? guestAccessToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<BoardingQrIssueResult> issueBoardingQr({
    required String bookingNumber,
    required String? guestAccessToken,
    bool forceReissue = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UrgentNegotiationStatus> getUrgentNegotiation({
    required String bookingNumber,
    String? guestAccessToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UrgentDecisionResult> submitUrgentDecision({
    required String bookingNumber,
    required String decision,
    String? guestAccessToken,
  }) {
    throw UnimplementedError();
  }
}

class _FailingCreateBookingApi extends _CapturingBookingApi {
  _FailingCreateBookingApi(this.error);

  final BookingApiException error;

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
    String? accessToken,
  }) {
    throw error;
  }
}

class _InquiryPricingApi extends _CapturingBookingApi {
  @override
  Future<PricingResult> calculatePricing({
    required String serviceTypeCode,
    required String vehicleTypeCode,
    int vehicleCount = 1,
    String? originAirportIata,
    String? destinationRegion,
    String? originLocationCode,
    String? destinationLocationCode,
    bool nameSign = false,
    String? scheduledPickupAt,
    int adults = 1,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
  }) {
    throw BookingApiException(
      'Pricing inquiry required for short distance',
      'INQUIRY_REQUIRED',
    );
  }
}

class _SuccessfulCreateBookingApi extends _CapturingBookingApi {
  Map<String, dynamic>? lastCreateRequest;

  @override
  Future<PricingResult> calculatePricing({
    required String serviceTypeCode,
    required String vehicleTypeCode,
    int vehicleCount = 1,
    String? originAirportIata,
    String? destinationRegion,
    String? originLocationCode,
    String? destinationLocationCode,
    bool nameSign = false,
    String? scheduledPickupAt,
    int adults = 1,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
  }) async {
    await super.calculatePricing(
      serviceTypeCode: serviceTypeCode,
      vehicleTypeCode: vehicleTypeCode,
      vehicleCount: vehicleCount,
      originAirportIata: originAirportIata,
      destinationRegion: destinationRegion,
      originLocationCode: originLocationCode,
      destinationLocationCode: destinationLocationCode,
      nameSign: nameSign,
      scheduledPickupAt: scheduledPickupAt,
      adults: adults,
      children: children,
      infants: infants,
      luggage20: luggage20,
      luggage24: luggage24,
      golfBags: golfBags,
      specialLuggageCount: specialLuggageCount,
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
    return const PricingResult(
      currency: 'THB',
      chargeItems: [
        ChargeLineItem(
          chargeType: 'VEHICLE_BASE',
          description: 'SEDAN CITY_TRANSFER (132.34 km est.)',
          quantity: 1,
          unitPrice: 1300,
          amount: 1300,
        ),
      ],
      totalAmount: 1300,
    );
  }

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
    String? accessToken,
  }) async {
    lastCreateRequest = Map<String, dynamic>.from(body);
    return const BookingCreateResult(
      bookingNumber: 'TX202607010001',
      status: 'OPEN',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1300,
      currency: 'THB',
      boardingQrToken: 'boarding-token',
      trustMessage: 'Pay the driver directly.',
    );
  }
}

class _MemoryBookingStateStorage extends BookingStateStorage {
  BookingWizardState? value;

  @override
  Future<void> save(BookingWizardState state) async {
    value = state;
  }

  @override
  Future<BookingWizardState?> load() async => value;

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _MemoryRecentLocationsRepository implements RecentLocationsRepository {
  final List<LocationOption> items = [];

  @override
  Future<void> add(LocationOption location) async {
    items.add(location);
  }

  @override
  Future<List<LocationOption>> load() async => items;
}

PlacesApiService _solynCentricPlacesApi() {
  return PlacesApiService.test(
    baseUrl: 'http://localhost:3000',
    client: MockClient((request) async {
      final uri = request.url;
      if (uri.path.endsWith('/places/details') &&
          uri.queryParameters['placeId'] == 'ChIJJciWWI6f4jARooYEqzN19NA') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'placeId': 'ChIJJciWWI6f4jARooYEqzN19NA',
              'name': 'Solyn Hotel',
              'formattedAddress': 'Bangkok, Thailand',
              'lat': 13.7730064,
              'lng': 100.5601678,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (uri.path.endsWith('/places/details') &&
          uri.queryParameters['placeId'] == 'ChIJZVKZKQGWAjERHntnx3WtANQ') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'placeId': 'ChIJZVKZKQGWAjERHntnx3WtANQ',
              'name': 'Centric Sea Pattaya',
              'formattedAddress': 'Pattaya, Thailand',
              'lat': 12.9395321,
              'lng': 100.8883189,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"success":false,"message":"not found"}', 404);
    }),
  );
}

LocationOption _solynHotelWithoutCoords() {
  return const LocationOption(
    id: 'place:ChIJJciWWI6f4jARooYEqzN19NA',
    displayName: 'Solyn Hotel',
    kind: LocationKind.place,
    placeId: 'ChIJJciWWI6f4jARooYEqzN19NA',
    name: 'Solyn Hotel',
    address: 'Bangkok, Thailand',
  );
}

LocationOption _centricSeaWithoutCoords() {
  return const LocationOption(
    id: 'place:ChIJZVKZKQGWAjERHntnx3WtANQ',
    displayName: 'Centric Sea Pattaya',
    kind: LocationKind.place,
    placeId: 'ChIJZVKZKQGWAjERHntnx3WtANQ',
    name: 'Centric Sea Pattaya',
    address: 'Pattaya, Thailand',
  );
}

BookingWizardState _cityTransferSubmitReadyState({
  required LocationOption origin,
  required LocationOption destination,
}) {
  return BookingWizardState(
    step: BookingWizardSteps.review,
    serviceType: BookingServiceType.cityTransfer,
    origin: origin,
    destination: destination,
    pickupDate: '2026-07-01',
    pickupTime: '09:30',
    selectedVehicle: 'SEDAN',
    adults: 2,
    customerName: 'Kim',
    customerPhone: '+66123456789',
    pricing: const PricingResult(
      currency: 'THB',
      chargeItems: [],
      totalAmount: 1300,
    ),
  );
}
