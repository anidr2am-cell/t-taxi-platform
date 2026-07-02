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

    expect(
      index,
      contains('<title>T-Ride - Thailand Airport Transfer</title>'),
    );
    expect(index, contains('apple-mobile-web-app-title" content="T-Ride"'));
    expect(manifest['name'], 'T-Ride - Thailand Airport Transfer');
    expect(manifest['short_name'], 'T-Ride');
  });
}
