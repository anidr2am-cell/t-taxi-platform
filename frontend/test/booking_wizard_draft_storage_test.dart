import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_wizard_test_helpers.dart';

class DraftTrackingApi implements BookingApiService {
  int pricingCalls = 0;
  int recommendationCalls = 0;

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
    recommendationCalls += 1;
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
    pricingCalls += 1;
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

class SuccessCreateApi extends DraftTrackingApi {
  SuccessCreateApi(this.onCreate);

  final void Function(Map<String, dynamic> body, String? idempotencyKey) onCreate;

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
    String? accessToken,
  }) async {
    onCreate(body, idempotencyKey);
    return BookingCreateResult(
      bookingId: 99,
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

class FailingCreateApi extends DraftTrackingApi {
  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
    String? accessToken,
  }) async {
    throw BookingApiException('Create failed');
  }
}

BookingWizardState sampleDraftState() {
  return BookingWizardState(
    step: 6,
    serviceType: BookingServiceType.airportPickup,
    origin: const LocationOption(
      id: 'airport:BKK',
      displayName: 'Suvarnabhumi Airport',
      kind: LocationKind.airport,
      code: 'BKK',
      placeId: 'google-BKK',
      name: 'Suvarnabhumi Airport',
      address: 'Suvarnabhumi Airport, Thailand',
      latitude: 13.6900,
      longitude: 100.7501,
    ),
    destination: const LocationOption(
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
    pickupDate: '2026-07-01',
    pickupTime: '09:30',
    adults: 2,
    children: 1,
    selectedVehicle: 'SUV',
    customerName: 'Kim Test',
    customerPhone: '+66123456789',
    flightNumber: 'TG409',
    additionalRequests: 'Need child seat',
  );
}

Map<String, dynamic> envelopeJson({
  required BookingWizardState state,
  required DateTime savedAt,
  DateTime? expiresAt,
  int version = BookingWizardDraftEnvelope.currentVersion,
}) {
  final envelope = BookingWizardDraftEnvelope(
    version: version,
    savedAt: savedAt.toUtc(),
    expiresAt: (expiresAt ?? savedAt.add(BookingWizardDraftEnvelope.ttl)).toUtc(),
    state: state,
  );
  return envelope.toJson();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookingStateStorage', () {
    test('A persists and restores draft input values', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.utc(2026, 7, 1, 8);
      final storage = BookingStateStorage(now: () => now);
      final state = sampleDraftState();

      await storage.save(state);
      final restored = await storage.load();

      expect(restored, isNotNull);
      expect(restored!.serviceType, BookingServiceType.airportPickup);
      expect(restored.origin?.code, 'BKK');
      expect(restored.destination?.code, 'PATTAYA');
      expect(restored.pickupDate, '2026-07-01');
      expect(restored.pickupTime, '09:30');
      expect(restored.selectedVehicle, 'SUV');
      expect(restored.customerName, 'Kim Test');
      expect(restored.customerPhone, '+66123456789');
      expect(restored.messengerId, '');
      expect(restored.flightNumber, 'TG409');
    });

    test('B clears expired draft on restore', () async {
      final state = sampleDraftState();
      final savedAt = DateTime.utc(2026, 7, 1, 8);
      final expiresAt = savedAt.add(BookingWizardDraftEnvelope.ttl);
      SharedPreferences.setMockInitialValues({
        BookingStateStorage.draftStorageKey: jsonEncode(
          envelopeJson(state: state, savedAt: savedAt, expiresAt: expiresAt),
        ),
      });

      final storage = BookingStateStorage(
        now: () => expiresAt.add(const Duration(minutes: 1)),
      );
      final restored = await storage.load();
      final prefs = await SharedPreferences.getInstance();

      expect(restored, isNull);
      expect(prefs.getString(BookingStateStorage.draftStorageKey), isNull);
    });

    test('C malformed JSON returns fresh null and clears storage', () async {
      SharedPreferences.setMockInitialValues({
        BookingStateStorage.draftStorageKey: '{not-json',
      });
      final storage = BookingStateStorage(now: () => DateTime.utc(2026, 7, 1, 8));

      final restored = await storage.load();
      final prefs = await SharedPreferences.getInstance();

      expect(restored, isNull);
      expect(prefs.getString(BookingStateStorage.draftStorageKey), isNull);
    });

    test('unsupported version is cleared safely', () async {
      final state = sampleDraftState();
      SharedPreferences.setMockInitialValues({
        BookingStateStorage.draftStorageKey: jsonEncode(
          envelopeJson(state: state, savedAt: DateTime.utc(2026, 7, 1, 8), version: 99),
        ),
      });
      final storage = BookingStateStorage(now: () => DateTime.utc(2026, 7, 1, 8));

      expect(await storage.load(), isNull);
    });

    test('D excludes transient pricing/recommendation/error from persisted envelope', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = BookingStateStorage(now: () => DateTime.utc(2026, 7, 1, 8));
      final state = sampleDraftState().copyWith(
        recommendation: const VehicleRecommendation(
          recommendedVehicle: 'SUV',
          selectableVehicles: ['SUV'],
          multipleVehicles: false,
          message: 'cached',
        ),
        pricing: const PricingResult(
          currency: 'THB',
          chargeItems: [],
          totalAmount: 999,
        ),
        errorMessage: 'ui_load_failed',
      );

      await storage.save(state);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(BookingStateStorage.draftStorageKey)!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final stateJson = Map<String, dynamic>.from(decoded['state'] as Map);

      expect(stateJson.containsKey('pricing'), isFalse);
      expect(stateJson.containsKey('recommendation'), isFalse);
      expect(stateJson.containsKey('errorMessage'), isFalse);
      expect(decoded['version'], BookingWizardDraftEnvelope.currentVersion);
      expect(decoded.containsKey('expiresAt'), isTrue);
    });

    test('G stores customer PII only inside TTL envelope', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = BookingStateStorage(now: () => DateTime.utc(2026, 7, 1, 8));
      await storage.save(sampleDraftState());

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(
        prefs.getString(BookingStateStorage.draftStorageKey)!,
      ) as Map<String, dynamic>;
      final stateJson = Map<String, dynamic>.from(decoded['state'] as Map);

      expect(stateJson['customerName'], 'Kim Test');
      expect(stateJson['customerPhone'], '+66123456789');
      expect(stateJson['messengerId'], '');
      expect(decoded['expiresAt'], isNotNull);
    });

    test('migrates legacy v1 draft into v2 envelope', () async {
      final state = sampleDraftState();
      SharedPreferences.setMockInitialValues({
        BookingStateStorage.legacyStorageKey: jsonEncode(state.toJson()),
      });
      final storage = BookingStateStorage(now: () => DateTime.utc(2026, 7, 1, 8));

      final restored = await storage.load();
      final prefs = await SharedPreferences.getInstance();

      expect(restored?.customerName, 'Kim Test');
      expect(prefs.getString(BookingStateStorage.legacyStorageKey), isNull);
      expect(prefs.getString(BookingStateStorage.draftStorageKey), isNotNull);
    });
  });

  group('BookingWizardController draft lifecycle', () {
    test('E keeps draft after create failure', () async {
      final storage = MemoryBookingStateStorage();
      final controller = await buildContractAirportPickupController(
        api: FailingCreateApi(),
        storage: storage,
      );
      controller.markInitializedForTest();

      final beforeName = controller.state.customerName;
      final result = await controller.submitBooking();

      expect(result, isNull);
      expect(storage.value?.customerName, beforeName);
      expect(storage.value?.origin?.code, 'BKK');
    });

    test('F clears draft only after create success', () async {
      final storage = MemoryBookingStateStorage();
      final api = SuccessCreateApi((body, idempotencyKey) {});
      final controller = await buildContractAirportPickupController(
        api: api,
        storage: storage,
      );
      controller.markInitializedForTest();

      expect(storage.value, isNotNull);
      final result = await controller.submitBooking();

      expect(result, isNotNull);
      expect(result!.bookingNumber, 'TX202607130001');
      expect(storage.value, isNull);
    });

    test('H and I restore draft then refetch recommendation and pricing', () async {
      final storage = MemoryBookingStateStorage();
      storage.value = sampleDraftState();
      final api = DraftTrackingApi();
      final controller = BookingWizardController(
        apiService: api,
        storage: storage,
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.initialize();

      expect(controller.state.customerName, 'Kim Test');
      expect(controller.state.pricing, isNotNull);
      expect(controller.state.recommendation, isNotNull);
      expect(api.recommendationCalls, greaterThan(0));
      expect(api.pricingCalls, greaterThan(0));
    });
  });
}
