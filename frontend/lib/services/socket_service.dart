import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

class SocketService {
  io.Socket? _socket;

  io.Socket connect() {
    if (_socket != null && _socket!.connected) return _socket!;

    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );
    return _socket!;
  }

  void joinRoom(String roomId, String role, String name) {
    _socket?.emit('join_room', {'roomId': roomId, 'role': role, 'name': name});
  }

  void sendMessage({
    required String roomId,
    required String message,
    required String senderRole,
    required String senderName,
    int? senderId,
  }) {
    _socket?.emit('send_message', {
      'roomId': roomId,
      'message': message,
      'senderRole': senderRole,
      'senderName': senderName,
      'senderId': senderId,
    });
  }

  void markRead(String roomId, String readerRole) {
    _socket?.emit('mark_read', {'roomId': roomId, 'readerRole': readerRole});
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  io.Socket? get socket => _socket;
}
