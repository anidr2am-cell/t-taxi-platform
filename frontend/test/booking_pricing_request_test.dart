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
  test('calculatePricing sends contract body with passengers, luggage, and options', () async {
    Uri? requestedUri;
    Map<String, dynamic>? body;
    final api = BookingApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        requestedUri = request.url;
        body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(jsonEncode({
          'success': true,
          'data': {
            'currency': 'THB',
            'chargeItems': [],
            'totalAmount': 0,
          },
        }), 200);
      }),
    );

    await api.calculatePricing(
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SUV',
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
  });

  test('wizard pricing maps Google airport place and Pattaya to MVP pricing codes', () async {
    final api = _CapturingBookingApi();
    final controller = BookingWizardController(
      apiService: api,
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
    );

    await controller.selectService(BookingServiceType.airportPickup);
    await controller.setOrigin(const LocationOption(
      id: 'place:bkk',
      displayName: 'Suvarnabhumi Airport, Bangkok, Thailand',
      kind: LocationKind.place,
      placeId: 'google-bkk',
      name: 'Suvarnabhumi Airport',
      address: 'Bangkok, Thailand',
    ));
    await controller.setDestination(const LocationOption(
      id: 'place:pattaya',
      displayName: '파타야',
      kind: LocationKind.place,
      code: 'PATTAYA',
      placeId: 'google-pattaya',
      name: '파타야',
      address: '파타야 촌 부리 태국',
    ));
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
  });

  test('place details keep localized display text while storing MVP internal code', () {
    final location = LocationOption.fromPlaceDetails(const PlaceDetails(
      placeId: 'google-pattaya',
      name: '파타야',
      address: '파타야 촌 부리 태국',
    ));

    expect(location.displayName, '파타야');
    expect(location.name, '파타야');
    expect(location.address, '파타야 촌 부리 태국');
    expect(location.code, 'PATTAYA');
    expect(location.placeId, 'google-pattaya');
  });
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
    lastPricingRequest = request;
    return const PricingResult(currency: 'THB', chargeItems: [], totalAmount: 0);
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
