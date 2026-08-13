import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_analytics.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';

void main() {
  group('BookingAnalytics', () {
    late RecordingBookingAnalyticsSink sink;
    late BookingAnalytics analytics;

    setUp(() {
      sink = RecordingBookingAnalyticsSink();
      analytics = BookingAnalytics(sink);
      analytics.resetSessionGuards();
    });

    test('booking_started fires once', () {
      analytics.trackBookingStarted(locale: 'en', deviceType: 'mobile');
      analytics.trackBookingStarted(locale: 'en', deviceType: 'mobile');

      expect(sink.named('booking_started'), hasLength(1));
      expect(sink.events.first.properties['locale'], 'en');
      expect(sink.events.first.properties['device_type'], 'mobile');
    });

    test('step viewed and completed include step metadata', () {
      analytics.trackStepViewed(stepNumber: 1, stepName: 'route');
      analytics.trackStepCompleted(
        stepNumber: 1,
        stepName: 'route',
        routeType: 'AIRPORT_PICKUP',
      );

      expect(sink.named('booking_step_viewed').single.properties['step_name'],
          'route');
      expect(
        sink.named('booking_step_completed').single.properties['route_type'],
        'AIRPORT_PICKUP',
      );
    });

    test('vehicle_selected and review_viewed properties', () {
      analytics.trackVehicleSelected(vehicleType: 'SUV', quotedPrice: 1500);
      analytics.trackBookingReviewViewed(
        vehicleType: 'SUV',
        routeType: 'CITY_TRANSFER',
      );

      expect(
        sink.named('vehicle_selected').single.properties['quoted_price'],
        1500,
      );
      expect(
        sink.named('booking_review_viewed').single.properties['vehicle_type'],
        'SUV',
      );
    });

    test('submit_attempted dedupes rapid clicks', () {
      analytics.trackBookingSubmitAttempted(vehicleType: 'SUV');
      analytics.trackBookingSubmitAttempted(vehicleType: 'SUV');
      expect(sink.named('booking_submit_attempted'), hasLength(1));
    });

    test('booking_completed only after success and dedupes replay', () {
      analytics.trackBookingCompleted(
        bookingId: 'TX202607010001',
        vehicleType: 'SUV',
        totalPrice: 1500,
      );
      analytics.trackBookingCompleted(
        bookingId: 'TX202607010001',
        vehicleType: 'SUV',
        totalPrice: 1500,
      );

      expect(sink.named('booking_completed'), hasLength(1));
      expect(
        sink.named('booking_completed').single.properties['booking_id'],
        'TX202607010001',
      );
    });

    test('booking_failed clears submit guard', () {
      analytics.trackBookingSubmitAttempted(vehicleType: 'SUV');
      analytics.trackBookingFailed(
        stepName: 'review',
        errorCategory: 'validation',
      );
      analytics.trackBookingSubmitAttempted(vehicleType: 'SUV');
      expect(sink.named('booking_submit_attempted'), hasLength(2));
    });

    test('booking_created and booking_completed fire on submit success', () {
      analytics.trackBookingCreated(
        bookingId: 'TX202607010001',
        vehicleType: 'SUV',
        totalPrice: 1500,
      );
      analytics.trackBookingCompleted(
        bookingId: 'TX202607010001',
        vehicleType: 'SUV',
        totalPrice: 1500,
      );

      expect(sink.named('booking_created'), hasLength(1));
      expect(sink.named('booking_completed'), hasLength(1));
    });

    test('contact connect funnel events include booking id only', () {
      analytics.trackContactConnectViewed(
        bookingId: 'TX202607010001',
        contactStatus: 'PENDING',
      );
      analytics.trackContactConnectStarted(
        bookingId: 'TX202607010001',
        channel: 'LINE',
      );
      analytics.trackContactConfirmRequested(
        bookingId: 'TX202607010001',
        channel: 'LINE',
      );
      analytics.trackContactConnectSucceeded(bookingId: 'TX202607010001');
      analytics.trackBookingFullyCompleted(
        bookingId: 'TX202607010001',
        vehicleType: 'SUV',
        totalPrice: 1500,
      );

      expect(sink.named('contact_connect_viewed').single.properties.keys,
          containsAll(['booking_id', 'contact_status']));
      expect(sink.named('booking_fully_completed'), hasLength(1));
      expect(
        sink.named('contact_connect_started').single.properties['channel'],
        'LINE',
      );
    });

    test('PII properties are stripped', () {
      analytics.track('booking_failed', {
        'step_name': 'customer',
        'customerName': 'Jane',
        'phone': '+66123456789',
        'messengerId': 'line-id',
        'flightNumber': 'TG401',
        'placeId': 'abc',
      });

      final props = sink.events.single.properties;
      expect(props.containsKey('customerName'), isFalse);
      expect(props.containsKey('phone'), isFalse);
      expect(props.containsKey('messengerId'), isFalse);
      expect(props.containsKey('flightNumber'), isFalse);
      expect(props.containsKey('placeId'), isFalse);
      expect(props['step_name'], 'customer');
    });
  });

  group('BookingWizardController analytics integration', () {
    test('selectVehicle and successful submit emit analytics', () async {
      final sink = RecordingBookingAnalyticsSink();
      final analytics = BookingAnalytics(sink);
      final controller = BookingWizardController(
        analytics: analytics,
        apiService: _SuccessBookingApi(),
        storage: _MemoryStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentRepo(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'bkk',
          displayName: 'Bangkok',
          kind: LocationKind.city,
          code: 'BANGKOK',
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
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'Jane Doe',
        phone: '+66123456789',
      );
      controller.markInitializedForTest();
      await controller.goToStep(BookingWizardSteps.review);

      final result = await controller.submitBooking();
      expect(result, isNotNull);

      expect(sink.named('vehicle_selected'), isNotEmpty);
      expect(sink.named('booking_submit_attempted'), hasLength(1));
      expect(sink.named('booking_created'), hasLength(1));
      expect(sink.named('booking_completed'), hasLength(1));
      expect(
        sink.named('booking_completed').single.properties.containsKey('phone'),
        isFalse,
      );
    });
  });
}

class _SuccessBookingApi implements BookingApiService {
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
      selectableVehicles: ['SUV'],
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
    return const PricingResult(
      currency: 'THB',
      chargeItems: [],
      totalAmount: 1500,
    );
  }

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    return const BookingCreateResult(
      bookingId: 1,
      bookingNumber: 'TX202607010001',
      guestAccessToken: 'guest',
      boardingQrToken: 'qr',
      status: 'PENDING',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1500,
      currency: 'THB',
      trustMessage: '',
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

class _MemoryStorage extends BookingStateStorage {
  @override
  Future<void> save(state) async {}

  @override
  Future<BookingWizardState?> load() async => null;

  @override
  Future<void> clear() async {}
}

class _MemoryRecentRepo implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption location) async {}

  @override
  Future<List<LocationOption>> load() async => [];
}
