import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/bookings/data/booking_api.dart';
import 'package:tride_driver/features/bookings/data/booking_repository.dart';

import 'test_fakes.dart';

void main() {
  ApiClient client(http.Client httpClient, {Duration? timeout}) => ApiClient(
    config: AppConfig.forEnvironment(AppEnvironment.stg),
    httpClient: httpClient,
    timeout: timeout ?? const Duration(seconds: 1),
  );

  FakeTokenStorage storage() => FakeTokenStorage(
    const AuthTokens(
      accessToken: 'fixture-token',
      refreshToken: 'fixture-refresh',
    ),
  );

  test('today API uses GET, bearer token, and parses success', () async {
    late http.Request request;
    final repository = BookingRepository(
      BookingApi(
        client: client(
          MockClient((incoming) async {
            request = incoming;
            return http.Response(
              '{"success":true,"data":{"date":"2026-07-18","items":[]}}',
              200,
            );
          }),
        ),
        storage: storage(),
      ),
    );

    final result = await repository.getTodayBookings();

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/driver/bookings/today');
    expect(request.url.query, isEmpty);
    expect(request.headers['authorization'], 'Bearer fixture-token');
    expect(result.items, isEmpty);
  });

  test(
    'detail API uses booking number in GET path and parses success',
    () async {
      late http.Request request;
      final response = bookingJson();
      response.addAll({
        'passengers': null,
        'luggage': null,
        'flight': null,
        'specialInstructions': null,
      });
      final responseBody = jsonEncode({'success': true, 'data': response});
      final repository = BookingRepository(
        BookingApi(
          client: client(
            MockClient((incoming) async {
              request = incoming;
              return http.Response.bytes(
                // This fixture is generated locally and contains no live data.
                utf8.encode(responseBody),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
          storage: storage(),
        ),
      );

      final result = await repository.getBookingDetail('TX202607180001');

      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/driver/bookings/TX202607180001');
      expect(result.summary.bookingNumber, 'TX202607180001');
    },
  );

  test('401 remains unauthorized for auth-expiry handling', () async {
    final api = BookingApi(
      client: client(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"UNAUTHORIZED"}',
            401,
          ),
        ),
      ),
      storage: storage(),
    );
    await expectLater(
      api.getTodayBookings(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test(
    'missing local access token is unauthorized without a request',
    () async {
      var requestCount = 0;
      final api = BookingApi(
        client: client(
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 200);
          }),
        ),
        storage: FakeTokenStorage(),
      );
      await expectLater(api.getTodayBookings(), throwsA(isA<ApiException>()));
      expect(requestCount, 0);
    },
  );

  test('timeout remains timeout and does not clear token', () async {
    final tokenStorage = storage();
    final api = BookingApi(
      client: client(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 1),
      ),
      storage: tokenStorage,
    );
    await expectLater(
      api.getTodayBookings(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.timeout,
        ),
      ),
    );
    expect(tokenStorage.clearCount, 0);
    expect(tokenStorage.tokens, isNotNull);
  });

  test('malformed API response is rejected', () async {
    final repository = BookingRepository(
      BookingApi(
        client: client(
          MockClient(
            (_) async => http.Response(
              '{"success":true,"data":{"date":"2026-07-18"}}',
              200,
            ),
          ),
        ),
        storage: storage(),
      ),
    );
    await expectLater(
      repository.getTodayBookings(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );
  });
}
