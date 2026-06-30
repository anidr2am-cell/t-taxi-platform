import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_pricing/pages/admin_pricing_manager_page.dart';
import 'package:frontend/features/admin_pricing/services/admin_pricing_api_service.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/screens/admin/admin_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, {Size size = const Size(1400, 900)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

Future<void> _configureLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return Future.value();
}

Future<void> _openSimulatorRouteDropdown(WidgetTester tester) async {
  await tester.tap(find.byKey(Key('simulator_route_dropdown:')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('BKK').last);
  await tester.pumpAndSettle();
}

Future<void> _openSimulatorVehicleDropdown(WidgetTester tester) async {
  await tester.tap(find.byKey(Key('simulator_vehicle_dropdown:')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('SEDAN').last);
  await tester.pumpAndSettle();
}

void main() {
  test('vehiclePriceStatus classifies current and future rows', () {
    expect(
      vehiclePriceStatus({'isActive': true, 'effectiveFrom': null, 'effectiveTo': null}),
      'current',
    );
    expect(
      vehiclePriceStatus({
        'isActive': true,
        'effectiveFrom': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      }),
      'future',
    );
    expect(vehiclePriceStatus({'isActive': false}), 'inactive');
  });

  testWidgets('AdminScreen pricing tab no longer shows legacy placeholder', (tester) async {
    await _configureLargeSurface(tester);

    SharedPreferences.setMockInitialValues({'admin_access_token': 'admin-token'});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vehicle Pricing'));
    await tester.pump();

    expect(find.text('Use admin pricing APIs'), findsNothing);
    expect(find.text('Admin login required'), findsNothing);
  });

  testWidgets('pricing manager shows loading then summary cards', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi(delay: const Duration(milliseconds: 20));
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Active routes'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Routes'), findsOneWidget);
    expect(find.text('Simulator'), findsOneWidget);
  });

  testWidgets('pricing manager shows error and retry', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi(error: const AdminPricingApiException('Boom'));
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Boom'), findsOneWidget);
    api.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Pricing Manager'), findsOneWidget);
  });

  testWidgets('routes tab handles empty list', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi(routes: const []);
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No routes found'), findsOneWidget);
  });

  testWidgets('simulator shows route not found style error', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi(
      simulateError: const AdminPricingApiException('Route not found for the given service and locations'),
    );
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simulator'));
    await tester.pumpAndSettle();
    await _openSimulatorRouteDropdown(tester);
    await _openSimulatorVehicleDropdown(tester);

    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Route not found'), findsOneWidget);
  });

  testWidgets('create route dialog validates required fields', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi();
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create route'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Origin is required'), findsOneWidget);
    expect(api.createRouteCalls, 0);
  });

  testWidgets('deactivate route shows confirm dialog', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi();
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(Icons.block).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.block).first);
    await tester.pumpAndSettle();
    expect(find.text('Deactivate route'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(api.updateRouteCalls, greaterThan(0));
  });

  testWidgets('simulator success shows total amount', (tester) async {
    await _configureLargeSurface(tester);
    final api = _FakePricingApi();
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simulator'));
    await tester.pumpAndSettle();
    await _openSimulatorRouteDropdown(tester);
    await _openSimulatorVehicleDropdown(tester);

    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();

    expect(find.text('Total: 800 THB'), findsOneWidget);
  });

  testWidgets('pricing manager routes tab has no horizontal overflow at 360px', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePricingApi();
    await tester.pumpWidget(_wrap(AdminPricingManagerPage(api: api), size: const Size(360, 800)));
    await tester.pumpAndSettle();

    expect(find.text('Active routes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakePricingApi implements AdminPricingApiService {
  _FakePricingApi({
    this.delay = Duration.zero,
    this.error,
    this.simulateError,
    this.routes,
  });

  final Duration delay;
  AdminPricingApiException? error;
  AdminPricingApiException? simulateError;
  List<dynamic>? routes;

  int createRouteCalls = 0;
  int updateRouteCalls = 0;

  @override
  Future<Map<String, dynamic>> copyRoute(int id, Map<String, dynamic> body) async =>
      {'route': _sampleRoute(), 'copiedVehiclePriceCount': 1};

  @override
  Future<Map<String, dynamic>> createChargePolicy(Map<String, dynamic> body) async => body;

  @override
  Future<Map<String, dynamic>> createRoute(Map<String, dynamic> body) async {
    createRouteCalls += 1;
    return _sampleRoute();
  }

  @override
  Future<Map<String, dynamic>> createVehiclePrice(Map<String, dynamic> body) async => body;

  @override
  Future<Map<String, dynamic>> getSummary() async {
    await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return {
      'activeRouteCount': 2,
      'activeVehiclePriceCount': 3,
      'activeChargePolicyCount': 1,
      'currentPriceCount': 2,
      'expiringSoonPriceCount': 0,
    };
  }

  @override
  Future<String?> getSavedToken() async => 'token';

  @override
  Future<List<dynamic>> listChargePolicies({bool includeInactive = true}) async => [
        {
          'id': 1,
          'chargeType': 'NIGHT',
          'calculationType': 'PERCENT_OF_BASE',
          'amount': 10,
          'isActive': true,
        },
      ];

  @override
  Future<List<dynamic>> listRoutes({bool includeInactive = true}) async =>
      routes ?? [_sampleRoute()];

  @override
  Future<List<dynamic>> listVehiclePrices({int? routeId, bool includeInactive = true}) async => [
        {
          'id': 10,
          'routeId': 1,
          'vehicleTypeId': 1,
          'vehicleTypeCode': 'SEDAN',
          'price': 800,
          'currency': 'THB',
          'isActive': true,
        },
      ];

  @override
  Future<Map<String, dynamic>> simulatePricing(Map<String, dynamic> body) async {
    if (simulateError != null) throw simulateError!;
    return {
      'matchedRoute': _sampleRoute(),
      'vehicleBasePrice': {'price': 800, 'currency': 'THB'},
      'chargeItems': [
        {'chargeType': 'VEHICLE_BASE', 'description': 'SEDAN', 'amount': 800},
      ],
      'subtotal': 800,
      'discount': 0,
      'totalAmount': 800,
      'currency': 'THB',
    };
  }

  @override
  Future<Map<String, dynamic>> updateChargePolicy(int id, Map<String, dynamic> body) async => body;

  @override
  Future<Map<String, dynamic>> updateRoute(int id, Map<String, dynamic> body) async {
    updateRouteCalls += 1;
    return {..._sampleRoute(), ...body};
  }

  @override
  Future<Map<String, dynamic>> updateVehiclePrice(int id, Map<String, dynamic> body) async => body;

  Map<String, dynamic> _sampleRoute() => {
        'id': 1,
        'serviceTypeCode': 'AIRPORT_PICKUP',
        'originLocationId': 1,
        'originLocationCode': 'BKK',
        'destinationLocationId': 8,
        'destinationLocationCode': 'PATTAYA',
        'isActive': true,
        'updatedAt': '2026-01-01T00:00:00.000Z',
      };
}
