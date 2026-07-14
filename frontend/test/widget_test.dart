import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/landing/widgets/landing_header.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart';
import 'package:frontend/providers/booking_provider.dart';

void main() {
  testWidgets('App loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleState()),
          ChangeNotifierProvider(create: (_) => BookingState()),
        ],
        child: const TTaxiApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('landing_header_logo')), findsOneWidget);
    expect(find.text('T-Ride'), findsNothing);
    final logo = tester.widget<Image>(
      find.byKey(const Key('landing_header_logo')),
    );
    expect((logo.image as AssetImage).assetName, LandingHeader.logoAssetPath);
  });

  test('web metadata uses T-Ride brand', () {
    final index = File('web/index.html').readAsStringSync();
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final driverManifest =
        jsonDecode(File('web/manifest-driver.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(index, contains('<title>T-Ride</title>'));
    expect(index, contains('apple-mobile-web-app-title" content="T-Ride"'));
    expect(index, contains('id = \'app-manifest\''));
    expect(index, contains('manifest-driver.json'));
    expect(
      index,
      contains('window.location.pathname.startsWith(\'/driver/\')'),
    );
    expect(manifest['name'], 'T-Ride');
    expect(manifest['short_name'], 'T-Ride');
    expect(manifest['id'], '/');
    expect(manifest['start_url'], '/');

    final icons = manifest['icons'] as List<dynamic>;
    expect(
      icons.firstWhere((icon) => icon['sizes'] == '192x192')['purpose'],
      'any',
    );
    expect(
      icons.firstWhere(
        (icon) => icon['src'] == 'icons/Icon-maskable-512.png',
      )['purpose'],
      'maskable',
    );

    expect(driverManifest['id'], '/driver');
    expect(driverManifest['name'], 'T-Ride Driver');
    expect(driverManifest['short_name'], 'T-Ride Driver');
    expect(driverManifest['start_url'], '/driver');
    expect(driverManifest['scope'], '/driver');

    final driverIcons = driverManifest['icons'] as List<dynamic>;
    expect(
      driverIcons.firstWhere((icon) => icon['sizes'] == '192x192')['purpose'],
      'any',
    );
    expect(
      driverIcons.firstWhere(
        (icon) => icon['src'] == '/icons/Icon-maskable-512.png',
      )['purpose'],
      'maskable',
    );
  });
}
