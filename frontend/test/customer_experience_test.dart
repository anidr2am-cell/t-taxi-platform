import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/booking/services/registered_airport_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/widgets/step_route_select.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/widgets/step_vehicle_select.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'support/booking_wizard_test_helpers.dart';

class _Prices extends CapturingBookingApi {
  _Prices({this.inquiry = false});
  final bool inquiry;
  final vehicles = <String>[];
  @override
  Future<VehicleRecommendation> recommendVehicle({
    required int adults,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) async => const VehicleRecommendation(
    recommendedVehicle: 'SUV',
    selectableVehicles: ['SUV', 'VAN'],
    multipleVehicles: false,
    message: 'OK',
    capacityRules: [
      {
        'vehicleCode': 'SEDAN',
        'passengers': 2,
        'luggage20': 2,
        'luggage24': 1,
        'golfBags': 2,
        'constraints': {'noLargeAtGolf': 2},
      },
      {
        'vehicleCode': 'SUV',
        'passengers': 3,
        'luggage20': 4,
        'luggage24': 4,
        'golfBags': 3,
        'constraints': {'maxCases': 4, 'maxCasesAndGolf': 6},
      },
      {
        'vehicleCode': 'VAN',
        'passengers': 8,
        'luggage20': 8,
        'luggage24': 8,
        'golfBags': 8,
        'constraints': {},
      },
    ],
  );

  @override
  Future<PricingResult> calculatePricing({
    Map<String, dynamic>? golf,
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
    vehicles.add(vehicleTypeCode);
    if (inquiry) throw BookingApiException('Contact us', 'INQUIRY_REQUIRED');
    return PricingResult(
      currency: 'THB',
      chargeItems: const [],
      totalAmount:
          ({'SEDAN': 1000, 'SUV': 1300, 'VAN': 1700}[vehicleTypeCode] ?? 0) +
          (nameSign ? 100 : 0),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    airportCatalogLoader = () async => {'BKK', 'DMK', 'UTP'};
  });
  tearDown(() => airportCatalogLoader = null);
  test(
    'all three fares use identical options and do not select an ineligible car',
    () async {
      final api = _Prices();
      final c = await buildContractAirportPickupController(api: api);
      expect(c.vehiclePrices.keys.toSet(), {'SEDAN', 'SUV', 'VAN'});
      expect(c.vehiclePrices['SEDAN']!.totalAmount, 1100);
      expect(c.vehiclePrices['SUV']!.totalAmount, 1400);
      expect(c.vehiclePrices['VAN']!.totalAmount, 1800);
      expect(c.isVehicleEnabled('SEDAN'), false);
      await c.selectVehicle('SEDAN');
      expect(c.state.selectedVehicle, 'SUV');
      c.dispose();
    },
  );
  for (final language in ['ko', 'en', 'th', 'ja', 'zh']) {
    testWidgets(
      'three cards at 375px in $language have fares and no server English',
      (tester) async {
        tester.view.physicalSize = const Size(375, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = await buildContractAirportPickupController(api: _Prices());
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => LocaleState()..setLanguage(language),
            child: MaterialApp(
              home: Scaffold(
                body: StepVehicleSelect(state: c.state, controller: c),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('฿1,100'), findsOneWidget);
        expect(find.text('฿1,400'), findsWidgets);
        expect(find.text('฿1,800'), findsOneWidget);
        expect(
          find.textContaining('is recommended for your party'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        c.dispose();
      },
    );
  }
  testWidgets('inquiry route displays inquiry on all three vehicle cards', (
    tester,
  ) async {
    final c = await buildContractAirportPickupController(
      api: _Prices(inquiry: true),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: Scaffold(
            body: StepVehicleSelect(state: c.state, controller: c),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.vehiclePrices, isEmpty);
    expect(c.vehiclePriceErrors.length, 3);
    expect(find.text('Contact us for a quote'), findsNWidgets(3));
    expect(c.state.pricing, isNull);
    c.dispose();
  });
  testWidgets('service preselection collapses list and change expands it', (
    tester,
  ) async {
    final c = BookingWizardController(
      storage: MemoryBookingStateStorage(),
      apiService: _Prices(),
    );
    await c.initialize(
      initialServiceType: BookingServiceType.airportPickup,
      freshEntry: true,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StepRouteSelect(
                state: c.state,
                controller: c,
                languageCode: 'en',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('City Transfer'), findsNothing);
    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    expect(find.text('City Transfer'), findsOneWidget);
    c.dispose();
  });
  test('fresh service entry clears old route even for same service', () async {
    final storage = MemoryBookingStateStorage();
    final c = await buildContractAirportPickupController(storage: storage);
    final next = BookingWizardController(
      storage: storage,
      apiService: _Prices(),
    );
    await next.initialize(
      initialServiceType: BookingServiceType.airportPickup,
      freshEntry: true,
    );
    expect(next.state.origin, isNull);
    expect(next.state.destination, isNull);
    expect(next.state.step, 0);
    c.dispose();
    next.dispose();
  });
}
