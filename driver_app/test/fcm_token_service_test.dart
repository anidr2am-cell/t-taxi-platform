import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/firebase/fcm_token_service.dart';
import 'package:tride_driver/core/network/api_exception.dart';

import 'test_fakes.dart';

void main() {
  test('registerIfNeeded requests permission, registers token, and stores deviceId',
      () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource();
    final storage = FakeTokenStorage(driverSession().tokens);
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(version: '2.3.4'),
    );

    await service.registerIfNeeded();

    expect(messaging.requestPermissionCount, 1);
    expect(messaging.getTokenCount, 1);
    expect(notificationApi.registerCount, 1);
    expect(notificationApi.lastRegisteredToken, 'fake-fcm-token');
    expect(notificationApi.lastRegisteredAppVersion, '2.3.4');
    expect(storage.notificationDeviceId, 7);
    expect(storage.notificationDeviceIdWriteCount, 1);

    await messaging.close();
    service.dispose();
  });

  test('registerIfNeeded skips registration when there is no session', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource();
    final storage = FakeTokenStorage();
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
    );

    await service.registerIfNeeded();

    expect(messaging.requestPermissionCount, 0);
    expect(notificationApi.registerCount, 0);
    expect(storage.notificationDeviceIdWriteCount, 0);

    await messaging.close();
    service.dispose();
  });

  test('registerIfNeeded fails quietly when registration throws', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource()
      ..registerError = const ApiException(ApiFailureKind.unavailable);
    final storage = FakeTokenStorage(driverSession().tokens);
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
      registrationRetryCooldown: const Duration(minutes: 5),
    );

    await expectLater(service.registerIfNeeded(), completes);
    expect(storage.notificationDeviceIdWriteCount, 0);
    expect(notificationApi.registerCount, 1);

    await messaging.close();
    service.dispose();
  });

  test('token refresh listener stays active after initial registration failure', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource()
      ..registerError = const ApiException(ApiFailureKind.unavailable);
    final storage = FakeTokenStorage(driverSession().tokens);
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
      registrationRetryCooldown: Duration.zero,
    );

    await service.registerIfNeeded();
    notificationApi.registerError = null;
    messaging.emitTokenRefresh('refreshed-after-failure');
    await Future<void>.delayed(Duration.zero);

    expect(notificationApi.registerCount, 2);
    expect(notificationApi.lastRegisteredToken, 'refreshed-after-failure');

    await messaging.close();
    service.dispose();
  });

  test('registerIfNeeded skips duplicate registration for unchanged token', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource();
    final storage = FakeTokenStorage(driverSession().tokens);
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
    );

    await service.registerIfNeeded();
    await service.registerIfNeeded();

    expect(notificationApi.registerCount, 1);
    expect(messaging.getTokenCount, 2);

    await messaging.close();
    service.dispose();
  });

  test('registerIfNeeded re-registers when FCM token changes on resume', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource();
    final storage = FakeTokenStorage(driverSession().tokens);
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
    );

    await service.registerIfNeeded();
    messaging.token = 'rotated-fcm-token';
    await service.registerIfNeeded();

    expect(notificationApi.registerCount, 2);
    expect(notificationApi.lastRegisteredToken, 'rotated-fcm-token');

    await messaging.close();
    service.dispose();
  });

  test('onTokenRefresh re-registers updated tokens', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource();
    final storage = FakeTokenStorage(driverSession().tokens);
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
    );

    await service.registerIfNeeded();
    messaging.emitTokenRefresh('refreshed-token');
    await Future<void>.delayed(Duration.zero);

    expect(notificationApi.registerCount, 2);
    expect(notificationApi.lastRegisteredToken, 'refreshed-token');

    await messaging.close();
    service.dispose();
  });

  test('deactivateStoredDevice deactivates and clears stored deviceId', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource();
    final storage = FakeTokenStorage(driverSession().tokens)
      ..notificationDeviceId = 15;
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
    );

    await service.deactivateStoredDevice(clearStoredId: true);

    expect(notificationApi.deactivateCount, 1);
    expect(notificationApi.lastDeactivatedDeviceId, 15);
    expect(storage.notificationDeviceId, isNull);
    expect(storage.notificationDeviceIdClearCount, 1);

    await messaging.close();
    service.dispose();
  });

  test('deactivateStoredDevice clears stored deviceId even when API fails', () async {
    final messaging = FakeFcmMessagingClient();
    final notificationApi = FakeNotificationDataSource()
      ..deactivateError = const ApiException(ApiFailureKind.unavailable);
    final storage = FakeTokenStorage(driverSession().tokens)
      ..notificationDeviceId = 15;
    final service = FcmTokenService(
      messaging: messaging,
      notificationApi: notificationApi,
      storage: storage,
      packageInfoProvider: () async => fakePackageInfo(),
    );

    await expectLater(service.deactivateStoredDevice(clearStoredId: true), completes);

    expect(notificationApi.deactivateCount, 1);
    expect(storage.notificationDeviceId, isNull);
    expect(storage.notificationDeviceIdClearCount, 1);

    await messaging.close();
    service.dispose();
  });
}
