import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/services/coupon_api_service.dart';
import 'package:frontend/features/account/services/mileage_api_service.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/widgets/step_confirmation.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';

import 'support/booking_wizard_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpConfirmation(
    WidgetTester tester, {
    required BookingWizardState state,
    int mileageBalance = 0,
    int mileageAmountToUse = 0,
    ValueChanged<int>? onMileageAmountChanged,
    num? estimatedTotal,
    num? mileageDiscount,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: Scaffold(
            body: StepConfirmation(
              state: state,
              mileageBalance: mileageBalance,
              mileageAmountToUse: mileageAmountToUse,
              onMileageAmountChanged: onMileageAmountChanged,
              estimatedTotal: estimatedTotal,
              mileageDiscount: mileageDiscount,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const pricingState = BookingWizardState(
    pricing: PricingResult(
      currency: 'THB',
      chargeItems: [],
      totalAmount: 1500,
    ),
  );

  final fixedNow = DateTime.utc(2026, 6, 29, 3);
  final futurePickup = DateTime(2026, 7, 1, 9, 30);

  Future<BookingWizardController> buildReviewReadyController({
    int totalAmount = 1500,
    int mileageBalance = 800,
    List<CustomerCouponItem> coupons = const [],
  }) async {
    final controller = BookingWizardController(
      now: () => fixedNow,
      apiService: _FixedPricingApi(totalAmount: totalAmount),
      storage: MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: MemoryRecentLocationsRepository(),
      ),
      mileageApiService: _StubMileageApiService(balance: mileageBalance),
      couponApiService: _StubCouponApiService(coupons: coupons),
    );

    final template = await buildContractAirportPickupController(
      api: _FixedPricingApi(totalAmount: totalAmount),
      now: () => fixedNow,
    );

    await controller.selectService(BookingServiceType.airportPickup);
    await controller.setOrigin(template.state.origin!);
    await controller.setDestination(template.state.destination!);
    await controller.setPickupDateTime(futurePickup);
    await controller.updateCustomerInfo(flightNumber: 'TG409');
    await controller.updatePassengersAndLuggage(adults: 2);
    await controller.loadRecommendation();
    await controller.selectVehicle('SUV');
    await controller.loadAvailableCoupons(accessToken: 'token');
    await controller.loadMileageBalance(accessToken: 'token');
    return controller;
  }

  group('StepConfirmation mileage UI', () {
    testWidgets('hides mileage section when balance is zero', (tester) async {
      await pumpConfirmation(
        tester,
        state: pricingState,
        mileageBalance: 0,
      );

      expect(find.text('Use mileage'), findsNothing);
      expect(find.text('Use all'), findsNothing);
    });

    testWidgets('shows mileage section when balance is positive', (
      tester,
    ) async {
      await pumpConfirmation(
        tester,
        state: pricingState,
        mileageBalance: 500,
      );

      expect(find.text('Use mileage'), findsWidgets);
      expect(find.text('Available mileage: 500 points'), findsOneWidget);
      expect(find.text('Use all'), findsOneWidget);
    });

    testWidgets('shows mileage discount row and reduced total', (
      tester,
    ) async {
      await pumpConfirmation(
        tester,
        state: pricingState.copyWith(mileageAmountToUse: 300),
        mileageBalance: 500,
        mileageAmountToUse: 300,
        estimatedTotal: 1200,
        mileageDiscount: 300,
      );

      expect(find.text('Mileage discount'), findsOneWidget);
      expect(find.text('-฿300'), findsOneWidget);
      expect(find.text('฿1,200'), findsOneWidget);
    });

    testWidgets('use all button invokes callback with full balance', (
      tester,
    ) async {
      int? captured;
      await pumpConfirmation(
        tester,
        state: pricingState,
        mileageBalance: 750,
        onMileageAmountChanged: (value) => captured = value,
      );

      await tester.scrollUntilVisible(
        find.text('Use all'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Use all'));
      await tester.pump();

      expect(captured, 750);
    });
  });

  group('BookingWizardController mileage', () {
    test('setMileageAmountToUse clamps to balance and payable amount', () async {
      final controller = await buildReviewReadyController(
        totalAmount: 1500,
        mileageBalance: 800,
      );

      controller.setMileageAmountToUse(2000);
      expect(controller.state.mileageAmountToUse, 800);

      controller.setMileageAmountToUse(500);
      expect(controller.state.mileageAmountToUse, 500);
    });

    test('setMileageAmountToUse clamps to payable after coupon', () async {
      final controller = await buildReviewReadyController(
        totalAmount: 1500,
        mileageBalance: 2000,
        coupons: const [
          CustomerCouponItem(
            id: 1,
            title: 'Save 500',
            discountAmount: 500,
            status: 'AVAILABLE',
          ),
        ],
      );

      controller.selectCoupon(1);
      controller.setMileageAmountToUse(1500);
      expect(controller.state.mileageAmountToUse, 1000);
      expect(controller.estimatedTotalAfterMileage(), 0);

      controller.setMileageAmountToUse(400);
      expect(controller.state.mileageAmountToUse, 400);
      expect(controller.estimatedTotalAfterMileage(), 600);
    });

    test('buildCreatePayload includes mileageAmount when positive', () async {
      final controller = await buildReviewReadyController();
      controller.setMileageAmountToUse(300);

      final payload = controller.buildCreatePayload();
      expect(payload['mileageAmount'], 300);
    });

    test('loadMileageBalance reclamps mileage when balance drops', () async {
      final mileageApi = _StubMileageApiService(balance: 2000);
      final controller = BookingWizardController(
        now: () => fixedNow,
        apiService: _FixedPricingApi(totalAmount: 1500),
        storage: MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: MemoryRecentLocationsRepository(),
        ),
        mileageApiService: mileageApi,
      );
      final template = await buildContractAirportPickupController(
        api: _FixedPricingApi(totalAmount: 1500),
        now: () => fixedNow,
      );
      await controller.selectService(BookingServiceType.airportPickup);
      await controller.setOrigin(template.state.origin!);
      await controller.setDestination(template.state.destination!);
      await controller.setPickupDateTime(futurePickup);
      await controller.updatePassengersAndLuggage(adults: 2);
      await controller.loadRecommendation();
      await controller.selectVehicle('SUV');
      await controller.loadMileageBalance(accessToken: 'token');
      controller.setMileageAmountToUse(500);
      mileageApi.balance = 200;
      await controller.loadMileageBalance(accessToken: 'token');

      expect(controller.mileageBalance, 200);
      expect(controller.state.mileageAmountToUse, 200);
    });
  });
}

class _FixedPricingApi implements BookingApiService {
  _FixedPricingApi({required this.totalAmount});

  final int totalAmount;

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
    return PricingResult(
      currency: 'THB',
      chargeItems: const [],
      totalAmount: totalAmount,
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

class _StubMileageApiService extends MileageApiService {
  _StubMileageApiService({required this.balance});

  int balance;

  @override
  Future<MileageBalanceResult> getMileageBalance() async {
    return MileageBalanceResult(balance: balance);
  }
}

class _StubCouponApiService extends CouponApiService {
  _StubCouponApiService({required this.coupons});

  final List<CustomerCouponItem> coupons;

  @override
  Future<List<CustomerCouponItem>> listCoupons() async => coupons;
}
