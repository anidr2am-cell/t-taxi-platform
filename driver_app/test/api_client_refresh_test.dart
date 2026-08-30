import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/auth/auth_token_refresher.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';

import 'test_fakes.dart';

void main() {
  final config = AppConfig.forEnvironment(AppEnvironment.stg);

  ApiClient buildClient({
    required http.Client httpClient,
    required FakeTokenStorage storage,
  }) {
    final refreshClient = ApiClient(config: config, httpClient: httpClient);
    final refresher = AuthTokenRefresher(
      storage: storage,
      client: refreshClient,
    );
    return ApiClient(
      config: config,
      httpClient: httpClient,
      tokenRefresher: refresher,
    );
  }

  test('401 refreshes access token and retries original request once', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired', refreshToken: 'refresh-token'),
    );
    var driverStatusCalls = 0;
    var refreshCalls = 0;

    final client = buildClient(
      storage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          expect(request.method, 'POST');
          return http.Response(
            '{"success":true,"data":{"accessToken":"fresh-token","expiresIn":3600}}',
            200,
          );
        }
        if (request.url.path.endsWith('/driver/status')) {
          driverStatusCalls++;
          final auth = request.headers['authorization'];
          if (auth == 'Bearer expired') {
            return http.Response(
              '{"success":false,"error_code":"UNAUTHORIZED"}',
              401,
            );
          }
          if (auth == 'Bearer fresh-token') {
            return http.Response(
              '{"success":true,"data":{"online":false}}',
              200,
            );
          }
        }
        return http.Response('{"success":false}', 500);
      }),
    );

    final response = await client.getJson(
      '/api/v1/driver/status',
      bearerToken: 'expired',
    );

    expect(response['success'], isTrue);
    expect(refreshCalls, 1);
    expect(driverStatusCalls, 2);
    expect(storage.tokens?.accessToken, 'fresh-token');
    expect(storage.tokens?.refreshToken, 'refresh-token');
    expect(storage.tokens?.accessTokenExpiresAt, isNotNull);
  });

  test('401 without refresh token still throws unauthorized', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired'),
    );
    final client = buildClient(
      storage: storage,
      httpClient: MockClient(
        (_) async => http.Response(
          '{"success":false,"error_code":"UNAUTHORIZED"}',
          401,
        ),
      ),
    );

    await expectLater(
      client.getJson('/api/v1/driver/status', bearerToken: 'expired'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test('failed refresh throws unauthorized for protected request', () async {
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
            '{"success":false,"error_code":"AUTH_INVALID"}',
            401,
          );
        }
        return http.Response(
          '{"success":false,"error_code":"UNAUTHORIZED"}',
          401,
        );
      }),
    );

    await expectLater(
      client.getJson('/api/v1/driver/status', bearerToken: 'expired'),
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

  test('concurrent 401 requests share a single refresh call', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired', refreshToken: 'refresh-token'),
    );
    var refreshCalls = 0;
    var protectedCalls = 0;
    final refreshGate = Completer<void>();

    final client = buildClient(
      storage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          await refreshGate.future;
          return http.Response(
            '{"success":true,"data":{"accessToken":"fresh-token","expiresIn":3600}}',
            200,
          );
        }
        if (request.url.path.endsWith('/driver/status')) {
          protectedCalls++;
          final auth = request.headers['authorization'];
          if (auth == 'Bearer expired') {
            return http.Response(
              '{"success":false,"error_code":"UNAUTHORIZED"}',
              401,
            );
          }
          return http.Response('{"success":true,"data":{"online":false}}', 200);
        }
        return http.Response('{"success":false}', 500);
      }),
    );

    final requests = List.generate(
      3,
      (_) => client.getJson('/api/v1/driver/status', bearerToken: 'expired'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    refreshGate.complete();
    await Future.wait(requests);

    expect(refreshCalls, 1);
    expect(protectedCalls, 6);
  });

  test('login 401 does not attempt refresh', () async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'expired', refreshToken: 'refresh-token'),
    );
    var refreshCalls = 0;
    final client = buildClient(
      storage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
        }
        return http.Response(
          '{"success":false,"error_code":"UNAUTHORIZED"}',
          401,
        );
      }),
    );

    await expectLater(
      client.postJson('/api/v1/auth/login', body: const {}),
      throwsA(isA<ApiException>()),
    );
    expect(refreshCalls, 0);
  });
}
