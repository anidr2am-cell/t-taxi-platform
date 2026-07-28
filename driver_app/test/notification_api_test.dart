import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/notifications/data/notification_api.dart';

import 'test_fakes.dart';

void main() {
  NotificationApi api(http.Client client) => NotificationApi(
    client: ApiClient(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      httpClient: client,
    ),
    storage: FakeTokenStorage(
      const AuthTokens(accessToken: 'notification-token', refreshToken: 'refresh'),
    ),
  );

  Map<String, dynamic> envelope(Object data) => {'success': true, 'data': data};

  test('registerDevice POST sends token, platform, and appVersion', () async {
    late http.Request request;
    final result = await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(
            envelope({
              'deviceId': 42,
              'platform': 'ANDROID',
              'token': 'abc***xyz',
            }),
          ),
          201,
        );
      }),
    ).registerDevice(
      token: 'fcm-token-123',
      appVersion: '1.2.3',
    );

    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/notifications/devices');
    expect(request.headers['authorization'], 'Bearer notification-token');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['token'], 'fcm-token-123');
    expect(body['platform'], 'ANDROID');
    expect(body['appVersion'], '1.2.3');
    expect(result.deviceId, 42);
    expect(result.platform, 'ANDROID');
  });

  test('registerDevice throws unauthorized when storage has no token', () async {
    final notificationApi = NotificationApi(
      client: ApiClient(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        httpClient: MockClient((_) async => http.Response('{}', 500)),
      ),
      storage: FakeTokenStorage(),
    );

    await expectLater(
      notificationApi.registerDevice(token: 'token'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test('registerDevice throws invalidResponse when deviceId is missing', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(jsonEncode(envelope({'platform': 'ANDROID'})), 201),
        ),
      ).registerDevice(token: 'token'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('deactivateDevice DELETE calls the device endpoint', () async {
    late http.Request request;
    await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(envelope({'deviceId': 42, 'active': false})),
          200,
        );
      }),
    ).deactivateDevice(42);

    expect(request.method, 'DELETE');
    expect(request.url.path, '/api/v1/notifications/devices/42');
    expect(request.headers['authorization'], 'Bearer notification-token');
  });

  test('deactivateDevice rejects invalid device ids', () async {
    await expectLater(
      api(MockClient((_) async => http.Response('{}', 200))).deactivateDevice(0),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.validation,
        ),
      ),
    );
  });

  test('deactivateDevice propagates server failures', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"NOT_FOUND"}',
            404,
          ),
        ),
      ).deactivateDevice(99),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.notFound,
        ),
      ),
    );
  });
}
