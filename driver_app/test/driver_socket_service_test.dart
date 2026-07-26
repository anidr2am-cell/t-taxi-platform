import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/dispatch/data/driver_socket_service.dart';

import 'test_fakes.dart';

void main() {
  test(
    'connects with JWT, subscribes, forwards events, and reports reconnect',
    () async {
      late _FakeSocketTransport transport;
      String? socketUrl;
      String? accessToken;
      final service = DriverSocketService(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        storage: FakeTokenStorage(
          const AuthTokens(accessToken: 'socket-jwt', refreshToken: 'refresh'),
        ),
        transportFactory: (url, token) {
          socketUrl = url;
          accessToken = token;
          return transport = _FakeSocketTransport();
        },
      );
      final received = <DriverSocketEvent>[];
      final subscription = service.events.listen(received.add);

      await service.connect();
      expect(socketUrl, 'https://trider.taxi');
      expect(accessToken, 'socket-jwt');
      expect(transport.connectCount, 1);
      expect(transport.emitted, [
        ('driver:calls:subscribe', const <String, dynamic>{}),
      ]);

      transport.trigger('driver:call:new', {'bookingNumber': 'TX209912319999'});
      await Future<void>.delayed(Duration.zero);
      expect(received.single.type, DriverSocketEventType.newCall);
      expect(received.single.payload['bookingNumber'], 'TX209912319999');

      transport.triggerConnect();
      await Future<void>.delayed(Duration.zero);
      expect(received.last.type, DriverSocketEventType.reconnected);
      expect(
        transport.emitted.where(
          (event) => event.$1 == 'driver:calls:subscribe',
        ),
        hasLength(2),
      );

      service.disconnect();
      expect(transport.disconnectCount, 1);
      expect(transport.disposeCount, 1);
      await subscription.cancel();
    },
  );

  test('missing token does not create a socket transport', () async {
    var factoryCalls = 0;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(),
      transportFactory: (_, _) {
        factoryCalls++;
        return _FakeSocketTransport();
      },
    );

    await service.connect();

    expect(factoryCalls, 0);
    expect(service.isConnected, isFalse);
  });

  test(
    'urgent socket events are subscribed but intentionally not forwarded',
    () async {
      late _FakeSocketTransport transport;
      final service = DriverSocketService(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
        transportFactory: (_, _) => transport = _FakeSocketTransport(),
      );
      final received = <DriverSocketEvent>[];
      final subscription = service.events.listen(received.add);
      await service.connect();

      transport.trigger('driver:urgent-call:new', {
        'bookingNumber': 'TX209912319999',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await subscription.cancel();
    },
  );
}

class _FakeSocketTransport implements DriverSocketTransport {
  final Map<String, List<void Function(Object?)>> _handlers = {};
  void Function()? _connectHandler;
  int connectCount = 0;
  int disconnectCount = 0;
  int disposeCount = 0;
  bool _connected = false;
  final List<(String, Object?)> emitted = [];

  @override
  bool get connected => _connected;

  @override
  void connect() {
    connectCount++;
    _connected = true;
    _connectHandler?.call();
  }

  void triggerConnect() {
    _connected = true;
    _connectHandler?.call();
  }

  void trigger(String event, Object? data) {
    for (final handler in _handlers[event] ?? const []) {
      handler(data);
    }
  }

  @override
  void disconnect() {
    disconnectCount++;
    _connected = false;
  }

  @override
  void dispose() {
    disposeCount++;
  }

  @override
  void emit(String event, Object? data) {
    emitted.add((event, data));
  }

  @override
  void on(String event, void Function(Object? data) handler) {
    (_handlers[event] ??= []).add(handler);
  }

  @override
  void onConnect(void Function() handler) {
    _connectHandler = handler;
  }
}
