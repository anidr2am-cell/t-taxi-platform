import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';
import '../../../core/storage/secure_token_storage.dart';

enum DriverSocketEventType {
  newCall,
  callClaimed,
  callConfirmed,
  assignmentReleased,
  urgentCallNew,
  urgentCallLocked,
  urgentCallEtaRequired,
  urgentCallRoundEnded,
  urgentCallConfirmed,
  urgentCallCancelled,
  urgentCallUnlocked,
  reconnected,
}

class DriverSocketEvent {
  const DriverSocketEvent(this.type, [this.payload = const {}]);

  final DriverSocketEventType type;
  final Map<String, dynamic> payload;
}

abstract interface class DriverSocketConnection {
  Stream<DriverSocketEvent> get events;
  bool get isConnected;
  Future<void> connect();
  void disconnect();
}

abstract interface class DriverSocketTransport {
  bool get connected;
  void onConnect(void Function() handler);
  void on(String event, void Function(Object? data) handler);
  void emit(String event, Object? data);
  void connect();
  void disconnect();
  void dispose();
}

typedef DriverSocketTransportFactory =
    DriverSocketTransport Function(String socketUrl, String accessToken);

class DriverSocketService implements DriverSocketConnection {
  DriverSocketService({
    required AppConfig config,
    required TokenStorage storage,
    DriverSocketTransportFactory? transportFactory,
  }) : _config = config,
       _storage = storage,
       _transportFactory = transportFactory ?? _createSocketIoTransport;

  final AppConfig _config;
  final TokenStorage _storage;
  final DriverSocketTransportFactory _transportFactory;
  final StreamController<DriverSocketEvent> _events =
      StreamController<DriverSocketEvent>.broadcast();

  DriverSocketTransport? _transport;
  DriverSocketTransport? _subscribedTransport;
  Future<void>? _connecting;
  bool _hasConnectedBefore = false;

  @override
  Stream<DriverSocketEvent> get events => _events.stream;

  @override
  bool get isConnected => _transport?.connected == true;

  @override
  Future<void> connect() {
    final active = _connecting;
    if (active != null) return active;

    final transport = _transport;
    if (transport != null) {
      if (transport.connected) return Future.value();
      final operation = _resumeTransport(transport);
      _connecting = operation;
      return operation.whenComplete(() {
        if (identical(_connecting, operation)) _connecting = null;
      });
    }

    final operation = _connect();
    _connecting = operation;
    return operation.whenComplete(() {
      if (identical(_connecting, operation)) _connecting = null;
    });
  }

  Future<void> _resumeTransport(DriverSocketTransport transport) async {
    if (!identical(_transport, transport) || transport.connected) return;
    transport.connect();
  }

  void _emitSubscribe(DriverSocketTransport transport) {
    if (identical(_subscribedTransport, transport)) return;
    transport.emit('driver:calls:subscribe', const <String, dynamic>{});
    _subscribedTransport = transport;
  }

  void _clearSubscribeState([DriverSocketTransport? transport]) {
    if (transport == null || identical(_subscribedTransport, transport)) {
      _subscribedTransport = null;
    }
  }

  Future<void> _connect() async {
    final accessToken = (await _storage.read())?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;

    final transport = _transportFactory(_config.socketBaseUrl, accessToken);
    _transport = transport;
    transport.onConnect(() {
      if (!identical(_transport, transport)) return;
      _emitSubscribe(transport);
      if (_hasConnectedBefore) {
        _add(const DriverSocketEvent(DriverSocketEventType.reconnected));
      }
      _hasConnectedBefore = true;
    });
    transport.on('connect_error', (data) {
      if (!identical(_transport, transport)) return;
      _clearSubscribeState(transport);
    });
    transport.on('disconnect', (data) {
      if (!identical(_transport, transport)) return;
      _clearSubscribeState(transport);
    });
    transport.on('driver:call:new', (data) {
      if (!identical(_transport, transport)) return;
      _add(DriverSocketEvent(DriverSocketEventType.newCall, _payload(data)));
    });
    transport.on('driver:urgent-call:new', (data) {
      if (!identical(_transport, transport)) return;
      _add(
        DriverSocketEvent(DriverSocketEventType.urgentCallNew, _payload(data)),
      );
    });
    _listen(
      transport,
      'driver:call:claimed',
      DriverSocketEventType.callClaimed,
    );
    _listen(
      transport,
      'driver:call:confirmed',
      DriverSocketEventType.callConfirmed,
    );
    _listen(
      transport,
      'driver:assignment:released',
      DriverSocketEventType.assignmentReleased,
    );
    for (final binding in const [
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
    ]) {
      _listen(transport, binding.$1, binding.$2);
    }
    transport.connect();
  }

  void _listen(
    DriverSocketTransport transport,
    String eventName,
    DriverSocketEventType type,
  ) {
    transport.on(eventName, (data) {
      if (!identical(_transport, transport)) return;
      _add(DriverSocketEvent(type, _payload(data)));
    });
  }

  Map<String, dynamic> _payload(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  void _add(DriverSocketEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void disconnect() {
    final transport = _transport;
    _transport = null;
    _clearSubscribeState(transport);
    transport
      ?..disconnect()
      ..dispose();
  }

  static DriverSocketTransport _createSocketIoTransport(
    String socketUrl,
    String accessToken,
  ) => SocketIoDriverSocketTransport(socketUrl, accessToken);
}

class SocketIoDriverSocketTransport implements DriverSocketTransport {
  SocketIoDriverSocketTransport(String socketUrl, String accessToken)
    : _socket = io.io(
        socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': accessToken})
            .disableAutoConnect()
            .enableForceNew()
            .enableReconnection()
            .build(),
      );

  final io.Socket _socket;

  @override
  bool get connected => _socket.connected;

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() => _socket.dispose();

  @override
  void emit(String event, Object? data) => _socket.emit(event, data);

  @override
  void on(String event, void Function(Object? data) handler) {
    _socket.on(event, handler);
  }

  @override
  void onConnect(void Function() handler) {
    _socket.onConnect((_) => handler());
  }
}
