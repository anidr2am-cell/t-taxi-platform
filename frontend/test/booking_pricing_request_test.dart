import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/place_prediction.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
      await controller.updateCustomerInfo(flightNumber: 'tg 401');
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');

      final payload = controller.buildCreatePayload();

      expect(payload['transfer'], isA<Map>());
      expect(payload['transfer']['flightNumber'], 'TG401');
    },
  );

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

  test('pickup time must be at least 2 hours from now', () async {
    final controller = BookingWizardController(
      apiService: _CapturingBookingApi(),
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    final ok = await controller.setPickupDateTime(
      DateTime(2026, 6, 29, 11, 30),
    );

    expect(ok, false);
    expect(controller.canProceedFromCurrentStep(), false);
    expect(controller.state.errorMessage, 'pickup_time_minimum');
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
      expect(controller.stepValidationMessageKey(5), 'wizard_required_vehicle');
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
      email: 'kim@example.com',
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
      await controller.updateCustomerInfo(name: 'Kim', phone: '+66123456789');

      final payload = controller.buildCreatePayload();
      final originPayload = Map<String, dynamic>.from(payload['origin'] as Map);
      final destinationPayload = Map<String, dynamic>.from(
        payload['destination'] as Map,
      );

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
        email: 'kim@example.com',
        phone: '+66123456789',
      );

      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(controller.state.step, 6);
      expect(controller.state.errorMessage, 'wizard_required_customer_name');
      expect(controller.state.errorMessage, isNot('Validation failed'));
    },
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
    lastPricingRequest = request;
    return const PricingResult(
      currency: 'THB',
      chargeItems: [],
      totalAmount: 0,
    );
  }

  @override
  Future<BookingCreateResult> createBooking(Map<String, dynamic> body) {
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
}

class _FailingCreateBookingApi extends _CapturingBookingApi {
  _FailingCreateBookingApi(this.error);

  final BookingApiException error;

  @override
  Future<BookingCreateResult> createBooking(Map<String, dynamic> body) {
    throw error;
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
