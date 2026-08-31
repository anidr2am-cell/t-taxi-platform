import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/app_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/api_exception.dart';
import 'package:frontend/core/network/auth_token_refresher.dart';
import 'package:frontend/core/network/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_token_storage.dart';

void main() {
  ApiClient buildClient({
    required http.Client httpClient,
    required FakeTokenStorage storage,
  }) {
    final refreshClient = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      httpClient: httpClient,
    );
    final refresher = AuthTokenRefresher(
      storage: storage,
      client: refreshClient,
    );
    return ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      httpClient: httpClient,
      tokenRefresher: refresher,
    );
  }

  test('401 refreshes customer access token and retries bookings request', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired', refreshToken: 'refresh-token'),
    );
    var bookingsCalls = 0;
    var refreshCalls = 0;

    final client = buildClient(
      storage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            '{"success":true,"data":{"accessToken":"fresh-token","expiresIn":3600}}',
            200,
          );
        }
        if (request.url.path.endsWith('/customer/bookings')) {
          bookingsCalls++;
          final auth = request.headers['authorization'];
          if (auth == 'Bearer expired') {
            return http.Response(
              '{"success":false,"error_code":"UNAUTHORIZED","message":"Invalid or expired token"}',
              401,
            );
          }
          if (auth == 'Bearer fresh-token') {
            return http.Response(
              '{"success":true,"data":{"bookings":[],"total":0,"page":1,"limit":20}}',
              200,
            );
          }
        }
        if (request.url.path.endsWith('/customer/mileage')) {
          final auth = request.headers['authorization'];
          if (auth == 'Bearer expired') {
            return http.Response(
              '{"success":false,"error_code":"UNAUTHORIZED","message":"Invalid or expired token"}',
              401,
            );
          }
          return http.Response(
            '{"success":true,"data":{"balance":500}}',
            200,
          );
        }
        return http.Response('{"success":false}', 500);
      }),
    );

    final bookingsResponse = await client.getJson(
      '/customer/bookings',
      bearerToken: 'expired',
      queryParameters: {'page': '1', 'limit': '20'},
    );
    expect(bookingsResponse['success'], isTrue);
    expect(refreshCalls, 1);
    expect(bookingsCalls, 2);
    expect(storage.tokens?.accessToken, 'fresh-token');

    final mileageResponse = await client.getJson(
      '/customer/mileage',
      bearerToken: 'fresh-token',
    );
    expect(mileageResponse['success'], isTrue);
    expect(refreshCalls, 1);
  });

  test('401 without refresh token still throws unauthorized for customer API', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired'),
    );
    final client = buildClient(
      storage: storage,
      httpClient: MockClient(
        (_) async => http.Response(
          '{"success":false,"error_code":"UNAUTHORIZED","message":"Invalid or expired token"}',
          401,
        ),
      ),
    );

    await expectLater(
      client.getJson('/customer/bookings', bearerToken: 'expired'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test('failed refresh throws unauthorized for customer bookings', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired', refreshToken: 'bad-refresh'),
    );
    var refreshCalls = 0;
    final client = buildClient(
      storage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            '{"success":false,"error_code":"AUTH_INVALID","message":"Invalid"}',
            401,
          );
        }
        return http.Response(
          '{"success":false,"error_code":"UNAUTHORIZED","message":"Invalid or expired token"}',
          401,
        );
      }),
    );

    await expectLater(
      client.getJson('/customer/bookings', bearerToken: 'expired'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
    expect(refreshCalls, 1);
  });
}
