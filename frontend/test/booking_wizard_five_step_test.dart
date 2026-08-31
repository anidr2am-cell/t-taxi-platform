import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/booking_wizard_route_args.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/widgets/booking_progress_header.dart';
import 'package:frontend/features/booking/widgets/step_pickup_datetime.dart';
import 'package:frontend/features/booking/widgets/wizard_status_views.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_wizard_test_helpers.dart';

Future<void> _scrollWizardDown(WidgetTester tester) async {
  final scrollView = tester.widget<SingleChildScrollView>(
    find.byType(SingleChildScrollView),
  );
  final controller = scrollView.controller;
  assert(controller != null);
  controller!.jumpTo(250);
  await tester.pumpAndSettle();
}

double _wizardScrollOffset(WidgetTester tester) {
  final scrollView = tester.widget<SingleChildScrollView>(
    find.byType(SingleChildScrollView),
  );
  return scrollView.controller?.offset ?? 0;
}

Future<BookingWizardController> _controllerAtScheduleStep() async {
  final controller = BookingWizardController(
    storage: MemoryBookingStateStorage(),
    recentLocationsStorage: RecentLocationsStorage(
      guestRepository: MemoryRecentLocationsRepository(),
    ),
    now: () => DateTime.utc(2026, 6, 29, 3),
  );
  controller.markInitializedForTest();
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
  await controller.goToStep(BookingWizardSteps.schedule);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('five-step booking wizard', () {
    test('stepCount is 5 and validation steps match semantic model', () {
      expect(BookingWizardState.stepCount, 5);
      expect(BookingWizardController.validationSteps, [0, 1, 2, 3, 4]);
      expect(BookingWizardController.preConfirmationSteps, [0, 1, 2, 3]);
      expect(BookingWizardSteps.migrateLegacyStep(7), BookingWizardSteps.review);
      expect(BookingWizardSteps.migrateLegacyStep(3), BookingWizardSteps.schedule);
    });

    testWidgets('shows progress header and route step first', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: const MaterialApp(home: BookingWizardPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BookingProgressHeader), findsOneWidget);
      expect(find.text('1/5 Route'), findsOneWidget);
      expect(find.text('Select date and time'), findsOneWidget);
    });

    testWidgets('CTA advances through steps when route is complete', (
      tester,
    ) async {
      final controller = BookingWizardController(
        storage: MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );
      controller.markInitializedForTest();
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

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(home: BookingWizardPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select date and time'));
      await tester.pumpAndSettle();

      expect(controller.state.step, BookingWizardSteps.schedule);
      expect(find.text('2/5 Date & time'), findsOneWidget);
    });

    testWidgets('resets scroll to top when advancing to the next step', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _controllerAtScheduleStep();

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(home: BookingWizardPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollWizardDown(tester);
      expect(_wizardScrollOffset(tester), greaterThan(0));

      await tester.tap(find.text('Select vehicle'));
      await tester.pumpAndSettle();

      expect(controller.state.step, BookingWizardSteps.vehicle);
      expect(_wizardScrollOffset(tester), 0);
      expect(find.text('Adults (12+)'), findsOneWidget);
    });

    testWidgets('resets scroll to top when going back to the previous step', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _controllerAtScheduleStep();
      await controller.goNext();
      expect(controller.state.step, BookingWizardSteps.vehicle);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(home: BookingWizardPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollWizardDown(tester);
      expect(_wizardScrollOffset(tester), greaterThan(0));

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(controller.state.step, BookingWizardSteps.schedule);
      expect(_wizardScrollOffset(tester), 0);
    });

    test('legacy draft step 7 restores to review step', () async {
      final saved = BookingWizardState(
        step: 7,
        serviceType: BookingServiceType.airportPickup,
        origin: const LocationOption(
          id: 'bkk',
          displayName: 'Suvarnabhumi Airport',
          kind: LocationKind.airport,
          code: 'BKK',
        ),
        destination: const LocationOption(
          id: 'pattaya',
          displayName: 'Pattaya',
          kind: LocationKind.city,
          code: 'PATTAYA',
        ),
        pickupDate: '2026-07-01',
        pickupTime: '09:30',
        customerName: 'Kim',
      );

      SharedPreferences.setMockInitialValues({
        BookingStateStorage.draftStorageKey: jsonEncode({
          'version': 2,
          'savedAt': DateTime.utc(2026, 7, 28).toIso8601String(),
          'expiresAt': DateTime.utc(2026, 7, 29).toIso8601String(),
          'state': saved.toJson(),
        }),
      });

      final now = () => DateTime.utc(2026, 7, 28, 3);
      final storage = BookingStateStorage(now: now);
      final controller = BookingWizardController(
        storage: storage,
        now: now,
      );
      await controller.initialize();

      expect(controller.state.step, BookingWizardSteps.review);
    });

    testWidgets('edit from review returns to review after CTA', (tester) async {
      final api = CapturingBookingApi();
      final controller = await buildReviewReadyController(api: api);
      await controller.goToStep(BookingWizardSteps.review);
      controller.markInitializedForTest();

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(home: BookingWizardPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      await controller.goToStepForEdit(BookingWizardSteps.vehicle);
      await tester.pumpAndSettle();
      expect(controller.state.step, BookingWizardSteps.vehicle);

      await tester.tap(find.textContaining('Enter passenger info'));
      await tester.pumpAndSettle();

      expect(controller.state.step, BookingWizardSteps.review);
    });

    testWidgets('/booking route opens wizard', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            initialRoute: '/booking',
            routes: {
              '/booking': (context) {
                final args = ModalRoute.of(context)?.settings.arguments;
                return BookingWizardPage(
                  routeArgs: args is BookingWizardRouteArgs ? args : null,
                );
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BookingWizardPage), findsOneWidget);
    });

    test('applyRoutePrefill replaces draft with fresh route-only state', () async {
      final storage = MemoryBookingStateStorage();
      await storage.save(
        BookingWizardState(
          step: BookingWizardSteps.customer,
          serviceType: BookingServiceType.airportPickup,
          customerName: 'Stale Name',
          customerPhone: '+66111111111',
          pickupDate: '20260101',
          pickupTime: '09:30',
          selectedVehicle: 'SUV',
          flightNumber: 'TG123',
          adults: 3,
        ),
      );
      final controller = BookingWizardController(
        storage: storage,
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: MemoryRecentLocationsRepository(),
        ),
        now: () => DateTime.utc(2026, 6, 29, 3),
      );

      const origin = LocationOption(
        id: 'bkk',
        displayName: 'Bangkok',
        kind: LocationKind.city,
        code: 'BANGKOK',
      );
      const destination = LocationOption(
        id: 'pattaya',
        displayName: 'Pattaya',
        kind: LocationKind.city,
        code: 'PATTAYA',
      );

      await controller.applyRoutePrefill(
        serviceType: BookingServiceType.cityTransfer,
        origin: origin,
        destination: destination,
        initialStep: BookingWizardSteps.schedule,
      );

      expect(controller.isInitialized, isTrue);
      expect(controller.state.step, BookingWizardSteps.schedule);
      expect(controller.state.serviceType, BookingServiceType.cityTransfer);
      expect(controller.state.origin, origin);
      expect(controller.state.destination, destination);
      expect(controller.state.customerName, '');
      expect(controller.state.customerPhone, '');
      expect(controller.state.selectedVehicle, isNull);
      expect(controller.state.flightNumber, '');
      expect(controller.state.adults, 1);
      expect(controller.state.pickupDate, isNot('20260101'));
      expect(storage.value!.customerName, '');
      expect(storage.value!.step, BookingWizardSteps.schedule);
    });

    testWidgets('routeArgs entry ignores stored draft and starts at schedule', (
      tester,
    ) async {
      final savedAt = DateTime.now().toUtc();
      final envelope = BookingWizardDraftEnvelope.create(
        state: const BookingWizardState(
          step: BookingWizardSteps.customer,
          serviceType: BookingServiceType.airportPickup,
          customerName: 'Stale Name',
          customerPhone: '+66111111111',
          pickupDate: '20260101',
          pickupTime: '09:30',
          selectedVehicle: 'SUV',
          flightNumber: 'TG123',
        ),
        savedAt: savedAt,
      );
      SharedPreferences.setMockInitialValues({
        BookingStateStorage.draftStorageKey: jsonEncode(envelope.toJson()),
      });

      const origin = LocationOption(
        id: 'bkk',
        displayName: 'Bangkok',
        kind: LocationKind.city,
        code: 'BANGKOK',
      );
      const destination = LocationOption(
        id: 'pattaya',
        displayName: 'Pattaya',
        kind: LocationKind.city,
        code: 'PATTAYA',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            home: BookingWizardPage(
              now: () => DateTime.utc(2026, 6, 29, 3),
              routeArgs: const BookingWizardRouteArgs(
                serviceType: BookingServiceType.cityTransfer,
                origin: origin,
                destination: destination,
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(WizardLoadingView).evaluate().isEmpty &&
            find.byType(StepPickupDateTime).evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.byType(StepPickupDateTime), findsOneWidget);
      expect(find.text('Stale Name'), findsNothing);
    });

    testWidgets('missing routeArgs restores stored draft', (tester) async {
      final savedAt = DateTime.now().toUtc();
      final envelope = BookingWizardDraftEnvelope.create(
        state: const BookingWizardState(
          step: BookingWizardSteps.customer,
          serviceType: BookingServiceType.airportPickup,
          customerName: 'Stored Name',
          customerPhone: '+66111111111',
          pickupDate: '20260701',
          pickupTime: '09:30',
        ),
        savedAt: savedAt,
      );
      SharedPreferences.setMockInitialValues({
        BookingStateStorage.draftStorageKey: jsonEncode(envelope.toJson()),
      });

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            home: BookingWizardPage(now: () => DateTime.utc(2026, 6, 29, 3)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stored Name'), findsOneWidget);
      expect(find.text('4/5 Passenger info'), findsOneWidget);
    });

    test('step navigation alone does not call pricing API', () async {
      final api = _PricingCallCounterApi();
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

      final callsBefore = api.pricingCalls;
      await controller.goNext();
      await controller.goBack();

      expect(api.pricingCalls, callsBefore);
    });

    test('same origin and destination blocks route step', () async {
      final controller = BookingWizardController(
        storage: MemoryBookingStateStorage(),
        recentLocationsStorage: RecentLocationsStorage(
          guestRepository: MemoryRecentLocationsRepository(),
        ),
      );
      const place = LocationOption(
        id: 'pattaya',
        displayName: 'Pattaya',
        kind: LocationKind.city,
        code: 'PATTAYA',
      );
      await controller.selectService(BookingServiceType.cityTransfer);
      await controller.setOrigin(place);
      await controller.setDestination(place);

      expect(controller.isSameOriginDestination, isTrue);
      expect(controller.canProceedFromStep(BookingWizardSteps.route), isFalse);
    });
  });
}

class _PricingCallCounterApi implements BookingApiService {
  int pricingCalls = 0;

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
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
  }) async {
    pricingCalls += 1;
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

Future<BookingWizardController> buildReviewReadyController({
  BookingApiService? api,
}) async {
  final controller = BookingWizardController(
    apiService: api ?? CapturingBookingApi(),
    storage: MemoryBookingStateStorage(),
    recentLocationsStorage: RecentLocationsStorage(
      guestRepository: MemoryRecentLocationsRepository(),
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
  return controller;
}

class MemoryBookingStateStorage extends BookingStateStorage {
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

class MemoryRecentLocationsRepository implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption location) async {}

  @override
  Future<List<LocationOption>> load() async => [];
}
