import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';

typedef DriverCallPayloadHandler = void Function(Map<String, dynamic> payload);

class DriverCallSocketService {
  io.Socket? _socket;
  Future<String?> Function()? _accessTokenLoader;
  DriverCallPayloadHandler? onNewCall;
  DriverCallPayloadHandler? onClaimed;
  DriverCallPayloadHandler? onConfirmed;
  DriverCallPayloadHandler? onAssignmentReleased;
  DriverCallPayloadHandler? onError;
  DriverCallPayloadHandler? onUrgentCallNew;
  DriverCallPayloadHandler? onUrgentCallLocked;
  DriverCallPayloadHandler? onUrgentCallEtaRequired;
  DriverCallPayloadHandler? onUrgentCallRoundEnded;
  DriverCallPayloadHandler? onUrgentCallConfirmed;
  DriverCallPayloadHandler? onUrgentCallCancelled;
  DriverCallPayloadHandler? onUrgentCallUnlocked;
  VoidCallback? onReconnect;

  Future<void> connect({
    String? accessToken,
    Future<String?> Function()? accessTokenLoader,
  }) async {
    _accessTokenLoader = accessTokenLoader;
    final token = accessToken ?? await _accessTokenLoader?.call() ?? '';
    disconnect();
    if (token.isEmpty) return;
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket!.onConnect((_) {
      _socket?.emit('driver:calls:subscribe');
      onReconnect?.call();
    });
    _socket!.onReconnect((_) async {
      await _applyLatestAuthToken();
      _socket?.emit('driver:calls:subscribe');
      onReconnect?.call();
    });
    _socket!.on('driver:call:new', (data) {
      if (data is Map) onNewCall?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('driver:call:claimed', (data) {
      if (data is Map) onClaimed?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('driver:call:confirmed', (data) {
      if (data is Map) onConfirmed?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('driver:assignment:released', (data) {
      if (data is Map) {
        onAssignmentReleased?.call(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('driver:calls:error', (data) {
      if (data is Map) onError?.call(Map<String, dynamic>.from(data));
    });
    _listenUrgent('driver:urgent-call:new', onUrgentCallNew);
    _listenUrgent('driver:urgent-call:locked', onUrgentCallLocked);
    _listenUrgent('driver:urgent-call:eta-required', onUrgentCallEtaRequired);
    _listenUrgent('driver:urgent-call:round-ended', onUrgentCallRoundEnded);
    _listenUrgent('driver:urgent-call:confirmed', onUrgentCallConfirmed);
    _listenUrgent('driver:urgent-call:cancelled', onUrgentCallCancelled);
    _listenUrgent('driver:urgent-call:unlocked', onUrgentCallUnlocked);
  }

  Future<void> _applyLatestAuthToken() async {
    final loader = _accessTokenLoader;
    if (loader == null) return;
    final freshToken = await loader();
    if (freshToken == null || freshToken.isEmpty) return;
    final socket = _socket;
    if (socket == null) return;
    socket.io.options?['auth'] = {'token': freshToken};
  }

  void _listenUrgent(String event, DriverCallPayloadHandler? handler) {
    _socket!.on(event, (data) {
      if (data is Map) handler?.call(Map<String, dynamic>.from(data));
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}

typedef VoidCallback = void Function();
