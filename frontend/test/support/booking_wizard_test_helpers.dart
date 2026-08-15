import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';

const bookingContractCustomerName = 'Kim Test';
const bookingContractCustomerPhone = '+66123456789';

class CapturingBookingApi implements BookingApiService {
  Map<String, dynamic>? lastPricingRequest;
  Map<String, dynamic>? lastCreateRequest;
  String? lastCreateIdempotencyKey;

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
      totalAmount: 1300,
    );
  }

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) {
    lastCreateRequest = Map<String, dynamic>.from(body);
    lastCreateIdempotencyKey = idempotencyKey;
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

class MemoryBookingStateStorage extends BookingStateStorage {
  BookingWizardState? value;

  @override
  Future<void> save(BookingWizardState state) async {
    value = BookingStateStorage.persistableState(state);
  }

  @override
  Future<BookingWizardState?> load() async => value;

  @override
  Future<void> clear() async {
    value = null;
  }
}

class MemoryRecentLocationsRepository implements RecentLocationsRepository {
  final List<LocationOption> items = [];

  @override
  Future<void> add(LocationOption location) async {
    items.add(location);
  }

  @override
  Future<List<LocationOption>> load() async => items;
}

Future<BookingWizardController> buildContractAirportPickupController({
  BookingApiService? api,
  BookingStateStorage? storage,
  DateTime Function()? now,
  String airportCode = 'BKK',
  String airportName = 'Suvarnabhumi Airport',
}) async {
  final controller = BookingWizardController(
    apiService: api ?? CapturingBookingApi(),
    storage: storage ?? MemoryBookingStateStorage(),
    recentLocationsStorage: RecentLocationsStorage(
      guestRepository: MemoryRecentLocationsRepository(),
    ),
    now: now ?? (() => DateTime.utc(2026, 6, 29, 3)),
  );

  await controller.selectService(BookingServiceType.airportPickup);
  await controller.setOrigin(
    LocationOption(
      id: 'airport:$airportCode',
      displayName: airportName,
      kind: LocationKind.airport,
      code: airportCode,
      placeId: 'google-$airportCode',
      name: airportName,
      address: '$airportName, Thailand',
      latitude: airportCode == 'DMK' ? 13.9126 : 13.6900,
      longitude: airportCode == 'DMK' ? 100.6068 : 100.7501,
    ),
  );
  await controller.setDestination(
    const LocationOption(
      id: 'place:pattaya',
      displayName: 'Pattaya',
      kind: LocationKind.place,
      code: 'PATTAYA',
      placeId: 'google-pattaya',
      name: 'Pattaya',
      address: 'Pattaya, Chon Buri, Thailand',
      latitude: 12.9236,
      longitude: 100.8825,
    ),
  );
  await controller.setPickupDateTime(DateTime(2026, 7, 1, 9, 30));
  await controller.updateCustomerInfo(flightNumber: 'TG409');
  await controller.updatePassengersAndLuggage(
    adults: 2,
    children: 1,
    infants: 0,
    luggage20: 1,
    luggage24: 2,
    golfBags: 1,
    specialLuggageCount: 1,
    nameSign: true,
    nameSignText: 'KIM FAMILY',
  );
  await controller.loadRecommendation();
  await controller.selectVehicle('SUV');
  await controller.updateCustomerInfo(
    name: bookingContractCustomerName,
    phone: bookingContractCustomerPhone,
    additionalRequests: 'Need child seat',
  );

  return controller;
}
