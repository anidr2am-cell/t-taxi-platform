import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';

import 'support/booking_wizard_test_helpers.dart';

class IdempotencyTrackingApi implements BookingApiService {
  final List<String?> idempotencyKeys = [];
  Map<String, dynamic>? lastCreateRequest;
  int createCallCount = 0;

  @override
  Future<VehicleRecommendation> recommendVehicle({
    required int adults,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) {
    return CapturingBookingApi().recommendVehicle(
      adults: adults,
      children: children,
      infants: infants,
      luggage20: luggage20,
      luggage24: luggage24,
      golfBags: golfBags,
      specialLuggageCount: specialLuggageCount,
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
  }) {
    return CapturingBookingApi().calculatePricing(
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
    );
  }

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    createCallCount += 1;
    lastCreateRequest = Map<String, dynamic>.from(body);
    idempotencyKeys.add(idempotencyKey);
    return BookingCreateResult(
      bookingId: 1,
      bookingNumber: 'TX202607130001',
      status: 'OPEN',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1300,
      currency: 'THB',
      guestAccessToken: 'guest-token',
      boardingQrToken: 'boarding-token',
      trustMessage: 'trust',
      isUrgentRequest: false,
      canCancel: true,
    );
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

class FailingThenSuccessfulApi extends IdempotencyTrackingApi {
  FailingThenSuccessfulApi(this.failuresBeforeSuccess);

  final int failuresBeforeSuccess;
  int failuresSeen = 0;

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    createCallCount += 1;
    idempotencyKeys.add(idempotencyKey);
    if (failuresSeen < failuresBeforeSuccess) {
      failuresSeen += 1;
      throw BookingApiException('Temporary network error');
    }
    lastCreateRequest = Map<String, dynamic>.from(body);
    return BookingCreateResult(
      bookingId: 1,
      bookingNumber: 'TX202607130001',
      status: 'OPEN',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1300,
      currency: 'THB',
      guestAccessToken: 'guest-token',
      boardingQrToken: 'boarding-token',
      trustMessage: 'trust',
      isUrgentRequest: false,
      canCancel: true,
    );
  }
}

class InProgressThenSuccessfulApi extends IdempotencyTrackingApi {
  InProgressThenSuccessfulApi(this.inProgressBeforeSuccess);

  final int inProgressBeforeSuccess;
  int inProgressSeen = 0;

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    createCallCount += 1;
    idempotencyKeys.add(idempotencyKey);
    if (inProgressSeen < inProgressBeforeSuccess) {
      inProgressSeen += 1;
      throw BookingApiException(
        'Booking creation is already in progress for this idempotency key',
        'IDEMPOTENCY_REQUEST_IN_PROGRESS',
      );
    }
    lastCreateRequest = Map<String, dynamic>.from(body);
    return BookingCreateResult(
      bookingId: 1,
      bookingNumber: 'TX202607130001',
      status: 'OPEN',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1300,
      currency: 'THB',
      guestAccessToken: 'guest-token',
      boardingQrToken: 'boarding-token',
      trustMessage: 'trust',
      isUrgentRequest: false,
      canCancel: true,
    );
  }
}

void main() {
  test('BookingApiService.generateIdempotencyKey returns UUID v4 format', () {
    final key = BookingApiService.generateIdempotencyKey();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(key),
      isTrue,
    );
  });

  test('submitBooking sends Idempotency-Key header on createBooking call', () async {
    final api = IdempotencyTrackingApi();
    final controller = await buildContractAirportPickupController(api: api);

    await controller.submitBooking();

    expect(api.createCallCount, 1);
    expect(api.idempotencyKeys.single, isNotNull);
    expect(api.idempotencyKeys.single, isNotEmpty);
    expect(api.lastCreateRequest?['serviceTypeCode'], 'AIRPORT_PICKUP');
    expect(api.lastCreateRequest?.containsKey('totalAmount'), isFalse);
  });

  test('submit retry reuses the same idempotency key', () async {
    final api = FailingThenSuccessfulApi(1);
    final controller = await buildContractAirportPickupController(api: api);

    final firstAttempt = await controller.submitBooking();
    expect(firstAttempt, isNull);
    final secondAttempt = await controller.submitBooking();

    expect(secondAttempt, isNotNull);
    expect(api.createCallCount, 2);
    expect(api.idempotencyKeys.length, 2);
    expect(api.idempotencyKeys[0], api.idempotencyKeys[1]);
  });

  test('meaningful booking change generates a new idempotency key on next submit', () async {
    final api = FailingThenSuccessfulApi(1);
    final controller = await buildContractAirportPickupController(api: api);

    await controller.submitBooking();
    await controller.setDestination(
      const LocationOption(
        id: 'place:rayong',
        displayName: 'Rayong',
        kind: LocationKind.place,
        code: 'RAYONG',
        placeId: 'google-rayong',
        name: 'Rayong',
        address: 'Rayong, Thailand',
        latitude: 12.6814,
        longitude: 101.2816,
      ),
    );
    await controller.submitBooking();

    expect(api.idempotencyKeys.length, 2);
    expect(api.idempotencyKeys[0], isNot(equals(api.idempotencyKeys[1])));
  });

  test(
    'submit retries IDEMPOTENCY_REQUEST_IN_PROGRESS with same key and limited backoff',
    () async {
      final api = InProgressThenSuccessfulApi(1);
      final controller = await buildContractAirportPickupController(api: api);

      final result = await controller.submitBooking();

      expect(result, isNotNull);
      expect(api.createCallCount, 2);
      expect(api.idempotencyKeys.length, 2);
      expect(api.idempotencyKeys[0], api.idempotencyKeys[1]);
    },
  );
}
