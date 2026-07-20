import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';

void main() {
  final config = AppConfig.forEnvironment(AppEnvironment.stg);

  test('converts 401 into unauthorized', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient(
        (_) async =>
            http.Response('{"success":false,"error_code":"UNAUTHORIZED"}', 401),
      ),
    );
    await expectLater(
      client.getJson('/api/v1/auth/me', bearerToken: 'token'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test('converts 403 into forbidden', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient(
        (_) async =>
            http.Response('{"success":false,"error_code":"FORBIDDEN"}', 403),
      ),
    );
    await expectLater(
      client.getJson('/api/v1/auth/me', bearerToken: 'token'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.forbidden,
        ),
      ),
    );
  });

  test('converts 404 into notFound', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient(
        (_) async => http.Response(
          '{"success":false,"error_code":"BOOKING_NOT_FOUND"}',
          404,
        ),
      ),
    );
    await expectLater(
      client.postJson('/api/v1/driver/bookings/TX209912319999/accept'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.notFound,
        ),
      ),
    );
  });

  test('converts 409 into conflict', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient(
        (_) async => http.Response(
          '{"success":false,"error_code":"BOOKING_NOT_ACCEPTABLE"}',
          409,
        ),
      ),
    );
    await expectLater(
      client.postJson('/api/v1/driver/bookings/TX209912319999/accept'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.conflict,
        ),
      ),
    );
  });

  test('allows POST without a JSON body', () async {
    late http.Request request;
    final client = ApiClient(
      config: config,
      httpClient: MockClient((incoming) async {
        request = incoming;
        return http.Response('{"success":true,"data":{}}', 200);
      }),
    );
    await client.postJson('/api/v1/driver/bookings/TX209912319999/accept');
    expect(request.method, 'POST');
    expect(request.body, isEmpty);
  });

  test('converts malformed JSON into invalidResponse', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient((_) async => http.Response('<html>', 502)),
    );
    await expectLater(
      client.postJson('/api/v1/auth/login', body: const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('converts server failure into server error', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      client.postJson('/api/v1/auth/login', body: const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.server,
        ),
      ),
    );
  });

  test('converts client connection failure into unavailable', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(
      client.postJson('/api/v1/auth/login', body: const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unavailable,
        ),
      ),
    );
  });

  test('converts request timeout into timeout error', () async {
    final client = ApiClient(
      config: config,
      httpClient: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      client.postJson('/api/v1/auth/login', body: const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.timeout,
        ),
      ),
    );
  });
}
