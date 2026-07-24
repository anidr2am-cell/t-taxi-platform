import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';

typedef DriverCallPayloadHandler = void Function(Map<String, dynamic> payload);

class DriverCallSocketService {
  io.Socket? _socket;
  DriverCallPayloadHandler? onNewCall;
  DriverCallPayloadHandler? onClaimed;
  DriverCallPayloadHandler? onConfirmed;
  DriverCallPayloadHandler? onAssignmentReleased;
  DriverCallPayloadHandler? onError;
  VoidCallback? onReconnect;

  Future<void> connect({required String accessToken}) async {
    disconnect();
    if (accessToken.isEmpty) return;
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket!.onConnect((_) {
      _socket?.emit('driver:calls:subscribe');
      onReconnect?.call();
    });
    _socket!.onReconnect((_) {
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
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}

typedef VoidCallback = void Function();
