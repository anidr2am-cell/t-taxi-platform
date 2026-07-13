import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/config/map_provider_config.dart';
import 'package:frontend/features/booking/models/location_option.dart';
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
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => MapLocationPicker.show(
                context,
                languageCode: 'en',
                reverseLookup: (_, _, _) async {
                  lookupCalls += 1;
                  return 'Bangkok, Thailand';
                },
              ),
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
