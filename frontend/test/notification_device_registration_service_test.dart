import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/notification/services/notification_device_registration_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('authenticated registration posts token and stores device id', () async {
    final requests = <http.Request>[];
    final service = NotificationDeviceRegistrationService(
      baseUrl: 'http://localhost:3000',
      messagingClient: _FakeMessagingClient(token: 'fcm-token-value-for-service-test'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({
          'success': true,
          'data': {'deviceId': 42, 'platform': 'WEB', 'token': 'abcd1234...'},
        }), 201);
      }),
    );

    final result = await service.enableAuthenticated(
      accessTokenLoader: () async => 'access-token',
    );

    expect(result.registered, isTrue);
    expect(requests.single.url.path, '/api/v1/notifications/devices');
    expect(requests.single.headers['Authorization'], 'Bearer access-token');
    expect(jsonDecode(requests.single.body)['token'], 'fcm-token-value-for-service-test');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('notification_device_id_authenticated'), 42);
  });

  test('permission denied does not call backend', () async {
    var calls = 0;
    final service = NotificationDeviceRegistrationService(
      baseUrl: 'http://localhost:3000',
      messagingClient: _FakeMessagingClient(status: AuthorizationStatus.denied),
      client: MockClient((request) async {
        calls += 1;
        return http.Response('{}', 200);
      }),
    );

    final result = await service.enableAuthenticated(accessTokenLoader: () async => 'token');

    expect(result.status, NotificationDeviceRegistrationStatus.permissionDenied);
    expect(calls, 0);
  });

  test('config missing returns controlled state without backend call', () async {
    var calls = 0;
    final service = NotificationDeviceRegistrationService(
      baseUrl: 'http://localhost:3000',
      messagingClient: _FakeMessagingClient(
        initStatus: NotificationDeviceRegistrationStatus.configMissing,
      ),
      client: MockClient((request) async {
        calls += 1;
        return http.Response('{}', 200);
      }),
    );

    final result = await service.enableGuest(
      bookingId: 10,
      guestAccessToken: 'guest-token',
    );

    expect(result.status, NotificationDeviceRegistrationStatus.configMissing);
    expect(calls, 0);
  });

  test('guest registration uses guest endpoint and token refresh re-registers', () async {
    final messaging = _FakeMessagingClient(token: 'initial-fcm-token-value');
    final paths = <String>[];
    final bodies = <Map<String, dynamic>>[];
    final service = NotificationDeviceRegistrationService(
      baseUrl: 'http://localhost:3000',
      messagingClient: messaging,
      client: MockClient((request) async {
        paths.add(request.url.path);
        bodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return http.Response(jsonEncode({
          'success': true,
          'data': {'deviceId': 77, 'platform': 'WEB', 'token': 'abcd1234...'},
        }), 201);
      }),
    );

    final result = await service.enableGuest(
      bookingId: 10,
      guestAccessToken: 'guest-token',
    );
    messaging.refresh('refreshed-fcm-token-value');
    await Future<void>.delayed(Duration.zero);

    expect(result.registered, isTrue);
    expect(paths, [
      '/api/v1/public/bookings/10/notification-devices',
      '/api/v1/public/bookings/10/notification-devices',
    ]);
    expect(bodies.map((body) => body['token']), [
      'initial-fcm-token-value',
      'refreshed-fcm-token-value',
    ]);
  });

  test('registration failure returns controlled failed state', () async {
    final service = NotificationDeviceRegistrationService(
      baseUrl: 'http://localhost:3000',
      messagingClient: _FakeMessagingClient(token: 'fcm-token-value-for-failure'),
      client: MockClient((request) async {
        return http.Response(jsonEncode({
          'success': false,
          'message': 'Registration failed',
        }), 500);
      }),
    );

    final result = await service.enableAuthenticated(
      accessTokenLoader: () async => 'access-token',
    );

    expect(result.status, NotificationDeviceRegistrationStatus.failed);
    expect(result.message, contains('Registration failed'));
  });
}

class _FakeMessagingClient implements PushMessagingClient {
  _FakeMessagingClient({
    this.token = 'fcm-token-value',
    this.status = AuthorizationStatus.authorized,
    this.initStatus,
  });

  final String token;
  final AuthorizationStatus status;
  final NotificationDeviceRegistrationStatus? initStatus;
  final _controller = StreamController<String>.broadcast();

  @override
  Future<NotificationDeviceRegistrationStatus?> initialize() async => initStatus;

  @override
  Future<NotificationSettings> requestPermission() async => _settings(status);

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _controller.stream;

  void refresh(String value) {
    _controller.add(value);
  }
}

NotificationSettings _settings(AuthorizationStatus status) {
  return NotificationSettings(
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.notSupported,
    authorizationStatus: status,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.notSupported,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    timeSensitive: AppleNotificationSetting.notSupported,
    criticalAlert: AppleNotificationSetting.notSupported,
    sound: AppleNotificationSetting.enabled,
    providesAppNotificationSettings: AppleNotificationSetting.notSupported,
  );
}
