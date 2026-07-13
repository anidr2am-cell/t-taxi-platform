import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/config/map_provider_config.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/services/current_location_service.dart';
import 'package:frontend/features/booking/services/device_locale_resolver.dart';
import 'package:frontend/features/booking/widgets/google_places_search_field.dart';
import 'package:frontend/features/booking/widgets/map_location_picker.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('origin can be selected from injected map picker', (
    tester,
  ) async {
    LocationOption? selected;
    final mapLocation = LocationOption.fromCoordinates(
      latitude: 13.6900,
      longitude: 100.7501,
      address: 'Suvarnabhumi Airport, Bangkok, Thailand',
    );
    await tester.pumpWidget(
      _host(
        GooglePlacesSearchField(
          label: 'Origin',
          languageCode: 'en',
          onSelected: (value) => selected = value,
          mapPicker: (_, _, _) async => mapLocation,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('select_location_on_map')));
    await tester.pumpAndSettle();

    expect(selected, same(mapLocation));
    expect(find.text('Suvarnabhumi Airport'), findsOneWidget);
  });

  testWidgets('destination can be selected from injected map picker', (
    tester,
  ) async {
    LocationOption? selected;
    final mapLocation = LocationOption.fromCoordinates(
      latitude: 12.9236,
      longitude: 100.8825,
      address: 'Pattaya, Chon Buri, Thailand',
    );
    await tester.pumpWidget(
      _host(
        GooglePlacesSearchField(
          label: 'Destination',
          languageCode: 'en',
          onSelected: (value) => selected = value,
          mapPicker: (_, _, _) async => mapLocation,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('select_location_on_map')));
    await tester.pumpAndSettle();

    expect(selected, same(mapLocation));
    expect(find.text('Pattaya'), findsOneWidget);
  });

  testWidgets('cancelled map selection keeps existing location', (
    tester,
  ) async {
    const existing = LocationOption(
      id: 'existing',
      displayName: 'Bangkok',
      kind: LocationKind.city,
    );
    var selectionCalls = 0;
    await tester.pumpWidget(
      _host(
        GooglePlacesSearchField(
          label: 'Origin',
          languageCode: 'en',
          selected: existing,
          onSelected: (_) => selectionCalls += 1,
          mapPicker: (_, _, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('select_location_on_map')));
    await tester.pumpAndSettle();

    expect(selectionCalls, 0);
    expect(
      find.byKey(const ValueKey('select_location_on_map')),
      findsOneWidget,
    );
  });

  testWidgets('reverse geocoding failure still returns coordinates', (
    tester,
  ) async {
    LocationOption? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await MapLocationPicker.show(
                  context,
                  languageCode: 'en',
                  reverseLookup: (_, _, _) async => throw Exception('offline'),
                );
              },
              child: const Text('Open map'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.latitude, closeTo(13.7563, 0.000001));
    expect(result!.longitude, closeTo(100.5018, 0.000001));
    expect(result!.address, contains('13.756300'));
  });

  testWidgets('map shows attribution and geocodes only once on confirmation', (
    tester,
  ) async {
    var lookupCalls = 0;
    String? requestedLanguage;
    LocationOption? result;
    final deviceLocale = DeviceLocaleResolver(
      primaryLocale: () => const Locale('th', 'TH'),
      bindingLocale: () => const Locale('ko', 'KR'),
      platformLocales: () => const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await MapLocationPicker.show(
                  context,
                  languageCode: 'ko',
                  initialLocation: LocationOption.fromCoordinates(
                    latitude: 13.7563,
                    longitude: 100.5018,
                    address: '방콕, 태국',
                  ),
                  deviceLocaleResolver: deviceLocale,
                  reverseLookup: (_, _, language) async {
                    requestedLanguage = language;
                    lookupCalls += 1;
                    return 'กรุงเทพมหานคร ประเทศไทย';
                  },
                );
              },
              child: const Text('Open map'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('openstreetmap_attribution')),
      findsOneWidget,
    );
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    expect(find.textContaining('flutter_map | ©'), findsOneWidget);
    expect(lookupCalls, 0);

    final mapRect = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(mapRect.center + const Offset(40, 20));
    await tester.pump();
    expect(lookupCalls, 0);

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();
    expect(lookupCalls, 1);
    expect(requestedLanguage, 'th');
    expect(result?.address, 'กรุงเทพมหานคร ประเทศไทย');
  });

  testWidgets('current location is requested only after the button is tapped', (
    tester,
  ) async {
    final locationProvider = _FakeCurrentLocationProvider(
      result: const CurrentLocationResult(
        latitude: 12.9236,
        longitude: 100.8825,
        accuracyMeters: 12,
      ),
    );
    var reverseLookupCalls = 0;
    String? requestedLanguage;
    LocationOption? result;
    final deviceLocale = DeviceLocaleResolver(
      primaryLocale: () => const Locale('th', 'TH'),
      bindingLocale: () => null,
      platformLocales: () => const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await MapLocationPicker.show(
                  context,
                  languageCode: 'ko',
                  currentLocationProvider: locationProvider,
                  deviceLocaleResolver: deviceLocale,
                  reverseLookup: (_, _, language) async {
                    reverseLookupCalls += 1;
                    requestedLanguage = language;
                    return 'เมืองพัทยา ประเทศไทย';
                  },
                );
              },
              child: const Text('Open map'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map_current_location')), findsOneWidget);
    expect(locationProvider.calls, 0);
    expect(reverseLookupCalls, 0);

    await tester.tap(find.byKey(const ValueKey('map_current_location')));
    await tester.pumpAndSettle();

    expect(locationProvider.calls, 1);
    expect(find.textContaining('12.923600'), findsOneWidget);
    expect(find.textContaining('100.882500'), findsOneWidget);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.mapController?.camera.center.latitude, closeTo(12.9236, 0.0001));
    expect(
      map.mapController?.camera.center.longitude,
      closeTo(100.8825, 0.0001),
    );
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(markerLayer.markers.single.point.latitude, 12.9236);
    expect(markerLayer.markers.single.point.longitude, 100.8825);
    expect(reverseLookupCalls, 0);

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(reverseLookupCalls, 1);
    expect(requestedLanguage, 'th');
    expect(result?.address, 'เมืองพัทยา ประเทศไทย');
    expect(result?.latitude, 12.9236);
    expect(result?.longitude, 100.8825);
  });

  testWidgets('current location ignores duplicate taps while locating', (
    tester,
  ) async {
    final pending = Completer<CurrentLocationResult>();
    final locationProvider = _FakeCurrentLocationProvider(
      future: pending.future,
    );
    await tester.pumpWidget(
      _mapHost(currentLocationProvider: locationProvider),
    );
    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('map_current_location')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map_current_location')));
    await tester.pump();

    expect(locationProvider.calls, 1);
    expect(
      find.byKey(const ValueKey('map_current_location_loading')),
      findsOneWidget,
    );

    pending.complete(
      const CurrentLocationResult(
        latitude: 13.7,
        longitude: 100.5,
        accuracyMeters: 10,
      ),
    );
    await tester.pumpAndSettle();
  });

  for (final testCase in <(CurrentLocationFailure, String)>[
    (
      CurrentLocationFailure.permissionRequired,
      'Location permission is required to use your current position.',
    ),
    (
      CurrentLocationFailure.permissionDenied,
      'Location permission was denied.',
    ),
    (
      CurrentLocationFailure.permissionPermanentlyDenied,
      'Allow location access in your browser or device settings.',
    ),
    (
      CurrentLocationFailure.serviceDisabled,
      'Device location services are turned off.',
    ),
    (
      CurrentLocationFailure.timeout,
      'Location request timed out. Please try again.',
    ),
    (
      CurrentLocationFailure.unavailable,
      'Your current location is unavailable.',
    ),
    (
      CurrentLocationFailure.requiresHttps,
      'Location is unavailable in this environment. Please try again from an HTTPS address.',
    ),
  ]) {
    testWidgets('${testCase.$1} keeps manual map selection available', (
      tester,
    ) async {
      final provider = _FakeCurrentLocationProvider(failure: testCase.$1);
      await tester.pumpWidget(_mapHost(currentLocationProvider: provider));
      await tester.tap(find.text('Open map'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map_current_location')));
      await tester.pumpAndSettle();

      expect(find.text(testCase.$2), findsWidgets);
      expect(find.text('Use this location'), findsOneWidget);
    });
  }

  testWidgets('low accuracy warns while keeping the selected coordinates', (
    tester,
  ) async {
    final provider = _FakeCurrentLocationProvider(
      result: const CurrentLocationResult(
        latitude: 13.7563,
        longitude: 100.5018,
        accuracyMeters: 250,
      ),
    );
    await tester.pumpWidget(_mapHost(currentLocationProvider: provider));
    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('map_current_location')));
    await tester.pumpAndSettle();

    expect(
      find.text('Location accuracy is low. Adjust the marker on the map.'),
      findsWidgets,
    );
    expect(find.textContaining('13.756300'), findsOneWidget);
  });

  testWidgets('closing after locating keeps the original selection outside', (
    tester,
  ) async {
    const existing = LocationOption(
      id: 'existing',
      displayName: 'Bangkok',
      kind: LocationKind.city,
      latitude: 13.7563,
      longitude: 100.5018,
      address: 'Bangkok, Thailand',
    );
    LocationOption? result = existing;
    final provider = _FakeCurrentLocationProvider(
      result: const CurrentLocationResult(
        latitude: 12.9236,
        longitude: 100.8825,
        accuracyMeters: 10,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result =
                    await MapLocationPicker.show(
                      context,
                      languageCode: 'en',
                      initialLocation: existing,
                      currentLocationProvider: provider,
                    ) ??
                    result;
              },
              child: const Text('Open map'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map_current_location')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(result, same(existing));
  });

  test('customer information guidance is localized', () {
    expect(
      AppLocalizations('ko').t('wizard_required_customer'),
      '고객님의 정보를 입력해 주세요.',
    );
    expect(
      AppLocalizations('en').t('wizard_required_customer'),
      'Please enter your information.',
    );
  });

  test('map-selected location persists through wizard JSON state', () {
    final location = LocationOption.fromCoordinates(
      latitude: 12.9236,
      longitude: 100.8825,
      address: 'Pattaya, Chon Buri, Thailand',
    );

    final restored = LocationOption.fromJson(location.toJson());

    expect(restored.address, location.address);
    expect(restored.latitude, 12.9236);
    expect(restored.longitude, 100.8825);
    expect(restored.code, 'PATTAYA');
  });

  test('default tile provider uses HTTPS and remains replaceable', () {
    expect(MapProviderConfig.tileUrlTemplate, startsWith('https://'));
    expect(
      MapProviderConfig.tileUrlTemplate,
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Widget _mapHost({required CurrentLocationProvider currentLocationProvider}) {
  return MaterialApp(
    locale: const Locale('en'),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => MapLocationPicker.show(
            context,
            languageCode: 'en',
            currentLocationProvider: currentLocationProvider,
            reverseLookup: (_, _, _) async => 'Selected address',
          ),
          child: const Text('Open map'),
        ),
      ),
    ),
  );
}

class _FakeCurrentLocationProvider implements CurrentLocationProvider {
  _FakeCurrentLocationProvider({this.result, this.future, this.failure});

  final CurrentLocationResult? result;
  final Future<CurrentLocationResult>? future;
  final CurrentLocationFailure? failure;
  int calls = 0;

  @override
  Future<CurrentLocationResult> locate() async {
    calls += 1;
    if (failure != null) throw CurrentLocationException(failure!);
    if (future != null) return future!;
    return result!;
  }
}
