import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';

typedef DriverLocationPayloadHandler = void Function(Map<String, dynamic> payload);

class DriverLocationSocketService {
  io.Socket? _socket;
  DriverLocationPayloadHandler? onAdminChanged;
  DriverLocationPayloadHandler? onGuestChanged;
  DriverLocationPayloadHandler? onError;
  VoidCallback? onStateChanged;
  bool _connected = false;

  bool get connected => _connected;

  Future<void> connect({
    String? accessToken,
    String? guestAccessToken,
  }) async {
    disconnect();
    final auth = <String, dynamic>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      auth['token'] = accessToken;
    } else if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      auth['guestAccessToken'] = guestAccessToken;
    }
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth(auth)
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket!.onConnect((_) {
      _connected = true;
      onStateChanged?.call();
    });
    _socket!.onDisconnect((_) {
      _connected = false;
      onStateChanged?.call();
    });
    _socket!.on('driver:location:changed', (data) {
      if (data is Map) onAdminChanged?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('booking:driver-location:changed', (data) {
      if (data is Map) onGuestChanged?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('driver-location:error', (data) {
      if (data is Map) onError?.call(Map<String, dynamic>.from(data));
    });
  }

  void subscribeAdmin() {
    _socket?.emit('driver-location:admin:subscribe');
  }

  void subscribeGuest(int bookingId) {
    _socket?.emit('booking:driver-location:subscribe', {'bookingId': bookingId});
  }

  void emitDriverLocation(Map<String, dynamic> payload) {
    _socket?.emit('driver:location:update', payload);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}

typedef VoidCallback = void Function();
