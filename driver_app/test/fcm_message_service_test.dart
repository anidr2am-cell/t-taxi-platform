import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/firebase/fcm_message_service.dart';

class FakeFcmMessageStreams implements FcmMessageStreams {
  FakeFcmMessageStreams({this.initialMessage});

  RemoteMessage? initialMessage;
  final StreamController<RemoteMessage> foregroundController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> openedAppController =
      StreamController<RemoteMessage>.broadcast();
  int onMessageListenCount = 0;
  int onMessageOpenedAppListenCount = 0;
  int getInitialMessageCount = 0;

  @override
  Stream<RemoteMessage> get onMessage {
    onMessageListenCount++;
    return foregroundController.stream;
  }

  @override
  Stream<RemoteMessage> get onMessageOpenedApp {
    onMessageOpenedAppListenCount++;
    return openedAppController.stream;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    getInitialMessageCount++;
    return initialMessage;
  }

  Future<void> close() async {
    await foregroundController.close();
    await openedAppController.close();
  }
}

RemoteMessage fcmMessage({required String notificationType}) {
  return RemoteMessage(data: {'notificationType': notificationType});
}

void main() {
  test('foreground onMessage does not navigate', () async {
    final streams = FakeFcmMessageStreams();
    final service = FcmMessageService(messaging: streams);
    var selectedTab = -1;

    await service.attachShellNavigator((index) => selectedTab = index);
    streams.foregroundController.add(
      fcmMessage(notificationType: 'DRIVER_CALL_AVAILABLE'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(selectedTab, -1);
    expect(service.listenersAttached, isTrue);

    service.dispose();
    await streams.close();
  });

  test('onMessageOpenedApp navigates to mapped tab', () async {
    final streams = FakeFcmMessageStreams();
    final service = FcmMessageService(messaging: streams);
    var selectedTab = -1;

    await service.attachShellNavigator((index) => selectedTab = index);
    streams.openedAppController.add(
      fcmMessage(notificationType: 'DRIVER_URGENT_CALL_NEW'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(selectedTab, 0);

    streams.openedAppController.add(
      fcmMessage(notificationType: 'ADMIN_RELEASED'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(selectedTab, 1);

    service.dispose();
    await streams.close();
  });

  test('getInitialMessage navigates after shell attach', () async {
    final streams = FakeFcmMessageStreams(
      initialMessage: fcmMessage(notificationType: 'ADMIN_RELEASED'),
    );
    final service = FcmMessageService(messaging: streams);
    var selectedTab = -1;

    await service.attachShellNavigator((index) => selectedTab = index);

    expect(streams.getInitialMessageCount, 1);
    expect(selectedTab, 1);

    service.dispose();
    await streams.close();
  });

  test('unknown notification types do not navigate', () async {
    final streams = FakeFcmMessageStreams(
      initialMessage: fcmMessage(notificationType: 'BOOKING_CONFIRMED'),
    );
    final service = FcmMessageService(messaging: streams);
    var selectedTab = -1;

    await service.attachShellNavigator((index) => selectedTab = index);
    streams.openedAppController.add(
      fcmMessage(notificationType: 'UNKNOWN_TYPE'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(selectedTab, -1);

    service.dispose();
    await streams.close();
  });

  test('attachShellNavigator registers listeners only once', () async {
    final streams = FakeFcmMessageStreams();
    final service = FcmMessageService(messaging: streams);
    var selectedTab = -1;

    await service.attachShellNavigator((index) => selectedTab = index);
    await service.attachShellNavigator((index) => selectedTab = index);

    expect(streams.onMessageListenCount, 1);
    expect(streams.onMessageOpenedAppListenCount, 1);

    streams.openedAppController.add(
      fcmMessage(notificationType: 'DRIVER_CALL_AVAILABLE'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(selectedTab, 0);

    streams.openedAppController.add(
      fcmMessage(notificationType: 'DRIVER_CALL_AVAILABLE'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(selectedTab, 0);

    service.dispose();
    await streams.close();
  });

  test('detachShellNavigator clears navigation callback', () async {
    final streams = FakeFcmMessageStreams();
    final service = FcmMessageService(messaging: streams);
    var selectedTab = -1;

    await service.attachShellNavigator((index) => selectedTab = index);
    service.detachShellNavigator();
    streams.openedAppController.add(
      fcmMessage(notificationType: 'ADMIN_RELEASED'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(selectedTab, -1);

    service.dispose();
    await streams.close();
  });
}
