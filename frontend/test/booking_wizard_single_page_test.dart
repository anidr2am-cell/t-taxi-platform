import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_complete_review.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/widgets/wizard_section_card.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('booking complete copy', () {
    testWidgets('copy button copies reservation number and shows snackbar', (
      tester,
    ) async {
      const bookingNumber = 'TX202607010001';
      String? copiedText;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = call.arguments['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BookingCompletePage(
            result: const BookingCreateResult(
              bookingId: 1,
              bookingNumber: bookingNumber,
              guestAccessToken: 'guest-token',
              boardingQrToken: 'boarding-token',
              chatRoomCode: 'room-1',
              status: 'PENDING',
              paymentMethod: 'PAY_DRIVER',
              paymentStatus: 'UNPAID',
              totalAmount: 1500,
              currency: 'THB',
              trustMessage: '',
            ),
            serviceLabel: 'Airport Pickup',
            originLabel: 'BKK',
            destinationLabel: 'Pattaya',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.pumpAndSettle();

      expect(copiedText, bookingNumber);
      expect(find.text('Reservation number copied'), findsOneWidget);
    });
  });

  group('single-page booking wizard', () {
    Future<void> pumpWizard(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: const MaterialApp(home: BookingWizardPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows 7 expanded sections without booking confirmation step', (
      tester,
    ) async {
      await pumpWizard(tester);

      expect(find.byType(WizardSectionCard), findsNWidgets(7));
      expect(find.text('Select Service Type'), findsOneWidget);
      expect(find.text('Customer Information'), findsOneWidget);
      expect(find.text('Select Vehicle'), findsOneWidget);
      expect(find.text('Booking Summary'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('allows customer input before pickup step is complete', (
      tester,
    ) async {
      await pumpWizard(tester);

      await tester.enterText(
        find.bySemanticsLabel('(Required) Name'),
        'Jane Doe',
      );
      await tester.pump();

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(
        find.text(
          'Complete service, origin, destination, pick-up time, and passengers first.',
        ),
        findsWidgets,
      );
    });

    testWidgets('confirm button disabled until all required fields complete', (
      tester,
    ) async {
      await pumpWizard(tester);

      final confirmButton = find.widgetWithText(
        ElevatedButton,
        'Confirm Booking',
      );
      expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

      await tester.tap(find.text('Airport Pickup'));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);
    });

    testWidgets('shows validation hints for incomplete sections', (
      tester,
    ) async {
      await pumpWizard(tester);

      await tester.tap(find.text('City Transfer'));
      await tester.pumpAndSettle();

      final confirmButton = find.widgetWithText(
        ElevatedButton,
        'Confirm Booking',
      );
      expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);
      expect(find.text('Please select an origin.'), findsOneWidget);
    });

    testWidgets('shows flight number prefix icon for airport pickup', (
      tester,
    ) async {
      final saved = BookingWizardState(
        serviceType: BookingServiceType.airportPickup,
        pickupDate: '2026-07-01',
        pickupTime: '09:30',
      );

      SharedPreferences.setMockInitialValues({
        'booking_wizard_state_v1': jsonEncode(saved.toJson()),
      });

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: const MaterialApp(home: BookingWizardPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.flight_outlined), findsOneWidget);
    });

    testWidgets('restores saved wizard state and clamps old step index', (
      tester,
    ) async {
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
        flightNumber: 'TG401',
        customerName: 'Kim',
      );

      SharedPreferences.setMockInitialValues({
        'booking_wizard_state_v1': jsonEncode(saved.toJson()),
      });

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: const MaterialApp(home: BookingWizardPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WizardSectionCard), findsNWidgets(7));
      expect(find.text('Kim'), findsOneWidget);
    });

    testWidgets('has no horizontal overflow at 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpWizard(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('booking complete review section', () {
    testWidgets(
      'shows review details without duplicating route summary fields',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: BookingCompletePage(
              result: const BookingCreateResult(
                bookingNumber: 'TX202607010001',
                status: 'PENDING',
                paymentMethod: 'PAY_DRIVER',
                paymentStatus: 'UNPAID',
                totalAmount: 1500,
                currency: 'THB',
                guestAccessToken: 'guest-token',
                chatRoomCode: 'room-1',
                boardingQrToken: 'boarding-token',
                trustMessage: '',
              ),
              serviceLabel: 'Airport Pickup',
              originLabel: 'BKK Airport',
              destinationLabel: 'Pattaya Hotel',
              review: const BookingCompleteReview(
                pickupDate: '2026-07-01',
                pickupTime: '09:30',
                serviceType: BookingServiceType.airportPickup,
                flightNumber: 'TG401',
                adults: 2,
                selectedVehicle: 'SUV',
                customerName: 'Kim',
                customerEmail: 'kim@example.com',
                customerPhone: '+66123456789',
                additionalRequests: 'Child seat',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Airport Pickup'), findsOneWidget);
        expect(find.text('BKK Airport'), findsOneWidget);
        expect(find.text('Pattaya Hotel'), findsOneWidget);
        expect(find.text('TG401'), findsOneWidget);
        expect(find.text('Kim'), findsOneWidget);
        expect(find.text('Child seat'), findsOneWidget);
        expect(find.text('1500 THB'), findsOneWidget);
      },
    );

    testWidgets('hides empty optional review rows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BookingCompletePage(
            result: const BookingCreateResult(
              bookingNumber: 'TX202607010001',
              status: 'PENDING',
              paymentMethod: 'PAY_DRIVER',
              paymentStatus: 'UNPAID',
              totalAmount: 1500,
              currency: 'THB',
              guestAccessToken: 'guest-token',
              chatRoomCode: 'room-1',
              boardingQrToken: 'boarding-token',
              trustMessage: '',
            ),
            serviceLabel: 'City Transfer',
            originLabel: 'Bangkok',
            destinationLabel: 'Pattaya',
            review: const BookingCompleteReview(
              pickupDate: '2026-07-01',
              pickupTime: '09:30',
              adults: 1,
              selectedVehicle: 'SUV',
              customerName: 'Kim',
              customerEmail: 'kim@example.com',
              customerPhone: '+66123456789',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flight Number'), findsNothing);
      expect(find.text('Children'), findsNothing);
      expect(find.text('Infants'), findsNothing);
    });

    testWidgets('review section has no horizontal overflow at 360px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: BookingCompletePage(
            result: const BookingCreateResult(
              bookingNumber: 'TX202607010001',
              status: 'PENDING',
              paymentMethod: 'PAY_DRIVER',
              paymentStatus: 'UNPAID',
              totalAmount: 1500,
              currency: 'THB',
              guestAccessToken: 'guest-token',
              chatRoomCode: 'room-1',
              boardingQrToken: 'boarding-token',
              trustMessage: '',
            ),
            serviceLabel: 'Airport Pickup',
            originLabel: 'BKK Airport',
            destinationLabel: 'Pattaya Hotel',
            review: const BookingCompleteReview(
              pickupDate: '2026-07-01',
              pickupTime: '09:30',
              serviceType: BookingServiceType.airportPickup,
              flightNumber: 'TG401',
              adults: 2,
              luggage20: 1,
              selectedVehicle: 'SUV',
              customerName: 'Kim Lee',
              customerEmail: 'kim@example.com',
              customerPhone: '+66123456789',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  test('recommendVehicle is not called without prerequisites', () async {
    var recommendCalls = 0;
    final api = _CountingBookingApi(onRecommend: () => recommendCalls += 1);
    final controller = BookingWizardController(
      apiService: api,
      storage: _MemoryBookingStateStorage(),
      recentLocationsStorage: RecentLocationsStorage(
        guestRepository: _MemoryRecentLocationsRepository(),
      ),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );

    await controller.loadRecommendation();
    expect(recommendCalls, 0);

    await controller.selectService(BookingServiceType.airportPickup);
    await controller.loadRecommendation();
    expect(recommendCalls, 0);

    await controller.updatePassengersAndLuggage(adults: 2);
    await controller.loadRecommendation();
    expect(recommendCalls, 0);
  });

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

  test('validationSteps covers 7 wizard sections', () {
    expect(BookingWizardState.stepCount, 7);
    expect(BookingWizardController.validationSteps, [0, 1, 2, 3, 4, 5, 6]);
  });

  test('passenger and luggage changes reload recommendation immediately', () async {
    var recommendCalls = 0;
    int? lastAdults;
    int? lastLuggage20;
    final api = _TrackingRecommendApi(
      onRecommend: (adults, luggage20) {
        recommendCalls += 1;
        lastAdults = adults;
        lastLuggage20 = luggage20;
      },
    );
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
    final baselineCalls = recommendCalls;

    await controller.updatePassengersAndLuggage(adults: 2, luggage20: 1);
    expect(recommendCalls - baselineCalls, 1);
    expect(lastAdults, 2);
    expect(lastLuggage20, 1);
    expect(controller.state.recommendation, isNotNull);

    await controller.updatePassengersAndLuggage(adults: 3);
    expect(recommendCalls - baselineCalls, 2);
    expect(lastAdults, 3);
    expect(controller.state.adults, 3);
    expect(controller.state.recommendation, isNotNull);
  });
}

class _TrackingRecommendApi implements BookingApiService {
  _TrackingRecommendApi({required this.onRecommend});

  final void Function(int adults, int luggage20) onRecommend;

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
    onRecommend(adults, luggage20);
    return VehicleRecommendation(
      recommendedVehicle: 'SUV',
      selectableVehicles: ['SUV', 'VAN'],
      multipleVehicles: false,
      message: 'adults=$adults luggage20=$luggage20',
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
}

class _CountingBookingApi implements BookingApiService {
  _CountingBookingApi({required this.onRecommend});

  final VoidCallback onRecommend;

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
    onRecommend();
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

class _CapturingBookingApi implements BookingApiService {
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
