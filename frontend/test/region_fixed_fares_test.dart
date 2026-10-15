import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/fare_inquiry_card.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/admin_pricing/pages/admin_region_fares_panel.dart';
import 'package:frontend/features/admin_pricing/services/admin_pricing_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget wrap(Widget child, String lang) => MaterialApp(
  locale: Locale(lang),
  supportedLocales: const [
    Locale('ko'),
    Locale('en'),
    Locale('zh'),
    Locale('ja'),
    Locale('th'),
  ],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
  routes: {'/support': (_) => const Scaffold(body: Text('support-page'))},
);

class RegionApi extends AdminRegionPricingApiService {
  int saves = 0;
  @override
  Future<List<dynamic>> listRegionFareCandidates() async => [];
  @override
  Future<List<dynamic>> listPricingRegions() async => [
    {
      'id': 1,
      'code': 'PATTAYA',
      'fare_location_code': 'PATTAYA',
      'priority': 10,
      'is_active': 1,
      'geometry': {
        'type': 'Circle',
        'lat': 12.9236,
        'lng': 100.8825,
        'radiusKm': 15,
      },
    },
  ];
  @override
  Future<List<dynamic>> listRoutes({bool includeInactive = true}) async => [
    {
      'id': 1,
      'serviceTypeCode': 'AIRPORT_PICKUP',
      'originLocationCode': 'BKK',
      'destinationLocationCode': 'PATTAYA',
    },
  ];
  @override
  Future<List<dynamic>> listVehiclePrices({
    int? routeId,
    bool includeInactive = true,
  }) async => [
    {'id': 1, 'routeId': 1, 'vehicleTypeCode': 'SEDAN', 'price': 1000},
  ];
  @override
  Future<void> updatePricingRegion(int id, Map<String, dynamic> body) async {
    saves++;
    expect(body['geometry']['radiusKm'], 15);
  }
}

void main() {
  for (final lang in ['ko', 'en', 'zh', 'ja', 'th']) {
    testWidgets(
      'inquiry has no price or booking action and wraps at 375: $lang',
      (t) async {
        t.view.physicalSize = const Size(375, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          wrap(
            FareInquiryCard(
              loadChannels: () async => const [
                ContactChannel(
                  code: 'LINE',
                  displayName: 'LINE',
                  addUrl: 'https://line.me/example',
                ),
              ],
            ),
            lang,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(find.textContaining('LINE'), findsOneWidget);
        expect(find.textContaining('1000'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'support fallback remains usable when no channels are configured',
    (t) async {
      await t.pumpWidget(
        wrap(FareInquiryCard(loadChannels: () async => []), 'ko'),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(OutlinedButton));
      await t.pumpAndSettle();
      expect(find.text('support-page'), findsOneWidget);
    },
  );
  testWidgets('admin sees original fixed fare and can save boundary', (
    t,
  ) async {
    final api = RegionApi();
    await t.pumpWidget(wrap(AdminRegionFaresPanel(api: api), 'ko'));
    await t.pumpAndSettle();
    expect(find.textContaining('1000'), findsOneWidget);
    await t.tap(find.byIcon(Icons.edit_outlined));
    await t.pumpAndSettle();
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    expect(api.saves, 1);
    expect(t.takeException(), isNull);
  });
}
