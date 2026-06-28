import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/services/places_api_service.dart';
import 'package:frontend/features/booking/widgets/google_places_search_field.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('autocomplete uses /api/v1/places/autocomplete with input and language query parameters', () async {
    Uri? requestedUri;
    final api = PlacesApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(jsonEncode({
          'success': true,
          'data': {
            'predictions': [
              {
                'placeId': 'place-1',
                'mainText': 'Pattaya Beach',
                'secondaryText': 'Chon Buri, Thailand',
              },
            ],
          },
        }), 200);
      }),
    );

    final results = await api.autocomplete(input: ' pattaya ', language: 'ko');

    expect(results.single.placeId, 'place-1');
    expect(requestedUri!.path, '/api/v1/places/autocomplete');
    expect(requestedUri!.queryParameters['input'], 'pattaya');
    expect(requestedUri!.queryParameters['language'], 'ko');
  });

  test('autocomplete does not request backend for input shorter than 2 characters', () async {
    var calls = 0;
    final api = PlacesApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        calls += 1;
        return http.Response('{}', 200);
      }),
    );

    final results = await api.autocomplete(input: 'p', language: 'ko');

    expect(results, isEmpty);
    expect(calls, 0);
  });

  testWidgets('places search shows loading, success results, and empty state', (tester) async {
    final completer = Completer<http.Response>();
    var requestCount = 0;
    final api = PlacesApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) {
        requestCount += 1;
        if (requestCount == 1) return completer.future;
        return Future.value(http.Response(jsonEncode({
          'success': true,
          'data': {'predictions': []},
        }), 200));
      }),
    );

    await tester.pumpWidget(_host(api));
    await tester.enterText(find.byType(TextField), 'pattaya');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    completer.complete(http.Response(jsonEncode({
      'success': true,
      'data': {
        'predictions': [
          {
            'placeId': 'place-1',
            'mainText': 'Pattaya Beach',
            'secondaryText': 'Chon Buri, Thailand',
          },
        ],
      },
    }), 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pattaya Beach'), findsOneWidget);
    expect(find.text('Chon Buri, Thailand'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('No locations found'), findsOneWidget);
  });

  testWidgets('places search shows controlled error state', (tester) async {
    final api = PlacesApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async => http.Response(jsonEncode({
        'success': false,
        'error_code': 'EXTERNAL_API_ERROR',
        'message': 'Google Places provider is not configured',
      }), 503)),
    );

    await tester.pumpWidget(_host(api));
    await tester.enterText(find.byType(TextField), 'pattaya');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.textContaining('Google Places provider is not configured'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

Widget _host(PlacesApiService api) {
  return MaterialApp(
    home: Scaffold(
      body: GooglePlacesSearchField(
        label: 'Destination',
        languageCode: 'ko',
        placesApi: api,
        onSelected: (_) {},
      ),
    ),
  );
}
