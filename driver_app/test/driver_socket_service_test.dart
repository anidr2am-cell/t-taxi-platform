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

      transport.simulateDisconnect();
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

  test('forwards all seven urgent socket events with payloads', () async {
    late _FakeSocketTransport transport;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
      transportFactory: (_, _) => transport = _FakeSocketTransport(),
    );
    final received = <DriverSocketEvent>[];
    final subscription = service.events.listen(received.add);
    await service.connect();

    final bindings = [
      ('driver:urgent-call:new', DriverSocketEventType.urgentCallNew),
      ('driver:urgent-call:locked', DriverSocketEventType.urgentCallLocked),
      (
        'driver:urgent-call:eta-required',
        DriverSocketEventType.urgentCallEtaRequired,
      ),
      (
        'driver:urgent-call:round-ended',
        DriverSocketEventType.urgentCallRoundEnded,
      ),
      (
        'driver:urgent-call:confirmed',
        DriverSocketEventType.urgentCallConfirmed,
      ),
      (
        'driver:urgent-call:cancelled',
        DriverSocketEventType.urgentCallCancelled,
      ),
      ('driver:urgent-call:unlocked', DriverSocketEventType.urgentCallUnlocked),
    ];
    for (final binding in bindings) {
      transport.trigger(binding.$1, {
        'bookingNumber': 'TX209912319999',
        'source': binding.$1,
      });
    }
    await Future<void>.delayed(Duration.zero);

    expect(received.map((event) => event.type), bindings.map((row) => row.$2));
    expect(
      received.every(
        (event) => event.payload['bookingNumber'] == 'TX209912319999',
      ),
      isTrue,
    );
    await subscription.cancel();
  });

  test('forwards assignment released payload including reasonCode', () async {
    late _FakeSocketTransport transport;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
      transportFactory: (_, _) => transport = _FakeSocketTransport(),
    );
    final received = <DriverSocketEvent>[];
    final subscription = service.events.listen(received.add);
    await service.connect();

    transport.trigger('driver:assignment:released', {
      'bookingNumber': 'TX209912319999',
      'reasonCode': 'ADMIN_RELEASED',
    });
    await Future<void>.delayed(Duration.zero);

    expect(received.single.type, DriverSocketEventType.assignmentReleased);
    expect(received.single.payload['bookingNumber'], 'TX209912319999');
    expect(received.single.payload['reasonCode'], 'ADMIN_RELEASED');
    await subscription.cancel();
  });

  test('does not create duplicate transport when already connected', () async {
    var factoryCalls = 0;
    late _FakeSocketTransport transport;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
      transportFactory: (_, _) {
        factoryCalls++;
        return transport = _FakeSocketTransport();
      },
    );

    await service.connect();
    await service.connect();

    expect(factoryCalls, 1);
    expect(transport.connectCount, 1);
    expect(service.isConnected, isTrue);
  });

  test('reconnects stale disconnected transport without creating a new socket',
      () async {
    var factoryCalls = 0;
    late _FakeSocketTransport transport;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
      transportFactory: (_, _) {
        factoryCalls++;
        return transport = _FakeSocketTransport();
      },
    );

    await service.connect();
    transport.simulateDisconnect();
    expect(service.isConnected, isFalse);

    await service.connect();

    expect(factoryCalls, 1);
    expect(transport.connectCount, 2);
    expect(service.isConnected, isTrue);
    expect(
      transport.emitted.where(
        (event) => event.$1 == 'driver:calls:subscribe',
      ),
      hasLength(2),
    );
  });

  test('connect succeeds after connect_error on existing transport', () async {
    late _FakeSocketTransport transport;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
      transportFactory: (_, _) => transport = _FakeSocketTransport(autoConnect: false),
    );

    await service.connect();
    expect(transport.connectCount, 1);
    expect(service.isConnected, isFalse);

    transport.trigger('connect_error', 'auth failed');
    await service.connect();

    expect(transport.connectCount, 2);
    transport.triggerConnect();
    expect(service.isConnected, isTrue);
    expect(
      transport.emitted.where(
        (event) => event.$1 == 'driver:calls:subscribe',
      ),
      hasLength(1),
    );
  });

  test('duplicate onConnect on same connection emits subscribe only once', () async {
    late _FakeSocketTransport transport;
    final service = DriverSocketService(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      storage: FakeTokenStorage(const AuthTokens(accessToken: 'socket-jwt')),
      transportFactory: (_, _) => transport = _FakeSocketTransport(),
    );

    await service.connect();
    transport.triggerConnect();
    transport.triggerConnect();

    expect(
      transport.emitted.where(
        (event) => event.$1 == 'driver:calls:subscribe',
      ),
      hasLength(1),
    );

    service.disconnect();
  });
}

class _FakeSocketTransport implements DriverSocketTransport {
  _FakeSocketTransport({this.autoConnect = true});

  final bool autoConnect;
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
    if (autoConnect) {
      _connected = true;
      _connectHandler?.call();
    }
  }

  void triggerConnect() {
    _connected = true;
    _connectHandler?.call();
  }

  void simulateDisconnect() {
    _connected = false;
    trigger('disconnect', 'transport disconnect');
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
