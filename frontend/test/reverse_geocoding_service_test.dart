import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/config/map_provider_config.dart';
import 'package:frontend/features/booking/services/reverse_geocoding_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'uses replaceable endpoint and identifies native T-Ride requests',
    () async {
      late http.Request captured;
      final service = ReverseGeocodingService(
        endpoint: 'https://geo.example.test/reverse',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({'display_name': 'Pattaya, Thailand'}),
            200,
          );
        }),
      );

      final result = await service.lookup(
        latitude: 12.9236,
        longitude: 100.8825,
        language: 'en',
      );

      expect(result, 'Pattaya, Thailand');
      expect(captured.url.origin, 'https://geo.example.test');
      expect(captured.url.path, '/reverse');
      expect(captured.url.queryParameters['accept-language'], 'en');
      expect(captured.headers['Accept-Language'], 'en');
      expect(
        captured.headers['User-Agent'],
        MapProviderConfig.applicationIdentifier,
      );
    },
  );

  test('same coordinates and language use one provider request', () async {
    var requests = 0;
    final service = ReverseGeocodingService(
      client: MockClient((_) async {
        requests += 1;
        return http.Response(jsonEncode({'display_name': 'Bangkok'}), 200);
      }),
    );

    final first = service.lookup(
      latitude: 13.7563,
      longitude: 100.5018,
      language: 'en',
    );
    final second = service.lookup(
      latitude: 13.7563,
      longitude: 100.5018,
      language: 'en',
    );

    expect(await first, 'Bangkok');
    expect(await second, 'Bangkok');
    expect(requests, 1);
  });

  test(
    'same coordinates with different languages use separate requests',
    () async {
      var requests = 0;
      final service = ReverseGeocodingService(
        client: MockClient((request) async {
          requests += 1;
          final language = request.url.queryParameters['accept-language'];
          return http.Response(
            jsonEncode({'display_name': 'address-$language'}),
            200,
          );
        }),
      );

      final korean = await service.lookup(
        latitude: 13.7563,
        longitude: 100.5018,
        language: 'ko',
      );
      final thai = await service.lookup(
        latitude: 13.7563,
        longitude: 100.5018,
        language: 'th',
      );

      expect(korean, 'address-ko');
      expect(thai, 'address-th');
      expect(requests, 2);
    },
  );

  test('timeout returns null without automatic retry', () async {
    var requests = 0;
    final service = ReverseGeocodingService(
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        requests += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{}', 200);
      }),
    );

    final first = await service.lookup(
      latitude: 13.7563,
      longitude: 100.5018,
      language: 'en',
    );
    final second = await service.lookup(
      latitude: 13.7563,
      longitude: 100.5018,
      language: 'en',
    );

    expect(first, isNull);
    expect(second, isNull);
    expect(requests, 1);
  });
}
