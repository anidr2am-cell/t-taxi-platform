import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedUtc = DateTime.utc(2026, 7, 23, 3, 0); // 10:00 Bangkok
  final urgentPickup = DateTime(2026, 7, 23, 11, 0);
  final standardPickup = DateTime(2026, 7, 23, 13, 0);

  group('booking wizard confirmation actions', () {
    Future<BookingWizardController> buildCompleteController({
      required DateTime pickup,
      int step = 0,
    }) async {
      final controller = BookingWizardController(
        now: () => fixedUtc,
        apiService: _StubBookingApi(),
        storage: _MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: _MemoryRecentLocationsRepository(),
        ),
      );
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(
        const LocationOption(
          id: 'bkk',
          displayName: 'Bangkok',
          kind: LocationKind.city,
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
      await controller.setPickupDateTime(pickup);
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.updateCustomerInfo(
        name: 'Jane Doe',
        phone: '+66123456789',
      );
      if (step == 7) {
        await controller.goToStep(7);
      }
      controller.markInitializedForTest();
      return controller;
    }

    Future<void> pumpWizard(
      WidgetTester tester,
      BookingWizardController controller,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            home: BookingWizardPage(controller: controller),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('urgent pickup with complete fields shows review button', (
      tester,
    ) async {
      final controller = await buildCompleteController(pickup: urgentPickup);
      await pumpWizard(tester, controller);

      expect(find.text('Review booking'), findsOneWidget);
      expect(find.text('Urgent request'), findsNothing);
      expect(find.text('Confirm booking'), findsNothing);
    });

    testWidgets('review button enters step 7 and shows urgent request only', (
      tester,
    ) async {
      final controller = await buildCompleteController(pickup: urgentPickup);
      await pumpWizard(tester, controller);

      await tester.tap(find.text('Review booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.state.step, 7);
      expect(find.text('Urgent request'), findsOneWidget);
      expect(find.text('Confirm booking'), findsNothing);
      expect(find.text('Review booking'), findsNothing);
    });

    testWidgets('standard pickup review enters step 7 with confirm only', (
      tester,
    ) async {
      final controller = await buildCompleteController(pickup: standardPickup);
      await pumpWizard(tester, controller);

      await tester.tap(find.text('Review booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.state.step, 7);
      expect(find.text('Confirm booking'), findsOneWidget);
      expect(find.text('Urgent request'), findsNothing);
      expect(find.text('Review booking'), findsNothing);
    });

    testWidgets('step 7 pickup change to urgent switches primary action', (
      tester,
    ) async {
      final controller = await buildCompleteController(
        pickup: standardPickup,
        step: 7,
      );
      await pumpWizard(tester, controller);

      expect(find.text('Confirm booking'), findsOneWidget);
      expect(find.text('Urgent request'), findsNothing);

      await controller.setPickupDateTime(urgentPickup);
      await tester.pump();

      expect(find.text('Urgent request'), findsOneWidget);
      expect(find.text('Confirm booking'), findsNothing);
    });

    testWidgets('step 7 pickup change to standard switches primary action', (
      tester,
    ) async {
      final controller = await buildCompleteController(
        pickup: urgentPickup,
        step: 7,
      );
      await pumpWizard(tester, controller);

      expect(find.text('Urgent request'), findsOneWidget);
      expect(find.text('Confirm booking'), findsNothing);

      await controller.setPickupDateTime(standardPickup);
      await tester.pump();

      expect(find.text('Confirm booking'), findsOneWidget);
      expect(find.text('Urgent request'), findsNothing);
    });

    testWidgets('edit from confirmation returns to review button flow', (
      tester,
    ) async {
      final controller = await buildCompleteController(
        pickup: urgentPickup,
        step: 7,
      );
      await pumpWizard(tester, controller);

      await controller.goToStep(1);
      await tester.pump();

      expect(controller.state.step, 1);
      expect(find.text('Review booking'), findsOneWidget);
      expect(find.text('Urgent request'), findsNothing);
    });
  });
}

class _StubBookingApi implements BookingApiService {
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
    return const PricingResult(
      currency: 'THB',
      chargeItems: [],
      totalAmount: 1500,
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
  @override
  Future<void> add(LocationOption location) async {}

  @override
  Future<List<LocationOption>> load() async => [];
}
