import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';
import '../models/chat_connection_state.dart';

typedef ChatSocketMessageHandler = void Function(Map<String, dynamic> payload);
typedef ChatSocketReadHandler = void Function(Map<String, dynamic> payload);
typedef ChatSocketErrorHandler = void Function(Map<String, dynamic> payload);
typedef ChatSocketVoidHandler = void Function();

/// Socket.IO client for booking-scoped chat (Pack 17).
class ChatSocketService {
  io.Socket? _socket;
  ChatConnectionState _state = ChatConnectionState.offline;
  String? _joinedBookingNumber;
  int? _joinedRoomId;

  ChatConnectionState get connectionState => _state;
  String? get joinedBookingNumber => _joinedBookingNumber;
  int? get joinedRoomId => _joinedRoomId;
  bool get isConnected => _state == ChatConnectionState.connected;

  ChatSocketVoidHandler? onConnectionStateChanged;
  ChatSocketVoidHandler? onReconnected;

  ChatSocketMessageHandler? _messageHandler;
  ChatSocketReadHandler? _readHandler;
  ChatSocketErrorHandler? _errorHandler;

  void _setState(ChatConnectionState next) {
    if (_state == next) return;
    _state = next;
    onConnectionStateChanged?.call();
  }

  io.Socket connect({
    String? accessToken,
    String? guestAccessToken,
  }) {
    if (_socket != null) {
      _detachSocketListeners();
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    final auth = <String, dynamic>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      auth['token'] = accessToken;
    } else if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      auth['guestAccessToken'] = guestAccessToken;
    }

    _setState(ChatConnectionState.connecting);

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
      _setState(ChatConnectionState.connected);
      if (_joinedBookingNumber != null) {
        joinRoom(_joinedBookingNumber!);
      }
    });

    _socket!.onDisconnect((_) {
      if (_socket != null) {
        _setState(ChatConnectionState.reconnecting);
      }
    });

    _socket!.onConnectError((_) {
      _setState(ChatConnectionState.error);
    });

    _socket!.onReconnect((_) {
      _setState(ChatConnectionState.connected);
      onReconnected?.call();
      if (_joinedBookingNumber != null) {
        joinRoom(_joinedBookingNumber!);
      }
    });

    _socket!.on('chat:message', (data) {
      if (data is Map && _messageHandler != null) {
        _messageHandler!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('chat:read-updated', (data) {
      if (data is Map && _readHandler != null) {
        _readHandler!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('chat:error', (data) {
      if (data is Map && _errorHandler != null) {
        _errorHandler!(Map<String, dynamic>.from(data));
      }
    });

    return _socket!;
  }

  void setHandlers({
    ChatSocketMessageHandler? onMessage,
    ChatSocketReadHandler? onReadUpdated,
    ChatSocketErrorHandler? onError,
  }) {
    _messageHandler = onMessage;
    _readHandler = onReadUpdated;
    _errorHandler = onError;
  }

  void joinRoom(
    String bookingNumber, {
    void Function(Map<String, dynamic> room)? onJoined,
  }) {
    _joinedBookingNumber = bookingNumber;
    if (_socket == null || !_socket!.connected) return;

    _socket!.emitWithAck('chat:join', {'bookingNumber': bookingNumber}, ack: (ack) {
      if (ack is Map && ack['ok'] == true) {
        final room = ack['room'];
        if (room is Map) {
          final map = Map<String, dynamic>.from(room);
          _joinedRoomId = map['roomId'] as int?;
          onJoined?.call(map);
        }
      }
    });
  }

  Future<Map<String, dynamic>?> sendMessageWithAck({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
  }) async {
    if (_socket == null || !_socket!.connected) return null;

    final completer = Completer<Map<String, dynamic>?>();
    _socket!.emitWithAck(
      'chat:send',
      {
        'bookingNumber': bookingNumber,
        'text': text,
        'clientMessageId': clientMessageId,
      },
      ack: (ack) {
        if (!completer.isCompleted) {
          if (ack is Map && ack['ok'] == true && ack['message'] is Map) {
            completer.complete(Map<String, dynamic>.from(ack['message'] as Map));
          } else {
            completer.complete(null);
          }
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  }

  void markRead({required String bookingNumber, required int upToMessageId}) {
    _socket?.emit('chat:read', {
      'bookingNumber': bookingNumber,
      'upToMessageId': upToMessageId,
    });
  }

  void leaveRoom() {
    if (_joinedRoomId != null) {
      _socket?.emit('chat:leave', {'roomId': _joinedRoomId});
    }
    _joinedBookingNumber = null;
    _joinedRoomId = null;
  }

  /// Test helper: mark room joined without a live socket emit.
  void debugMarkJoined(String bookingNumber, int roomId) {
    _joinedBookingNumber = bookingNumber;
    _joinedRoomId = roomId;
  }

  void _detachSocketListeners() {
    if (_socket == null) return;
    _socket!.off('connect');
    _socket!.off('disconnect');
    _socket!.off('connect_error');
    _socket!.off('reconnect');
    _socket!.off('chat:message');
    _socket!.off('chat:read-updated');
    _socket!.off('chat:error');
  }

  void disconnect() {
    leaveRoom();
    _detachSocketListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _messageHandler = null;
    _readHandler = null;
    _errorHandler = null;
    _setState(ChatConnectionState.offline);
  }

  /// Test helper: simulate an incoming chat:message without a live socket.
  void debugInjectMessage(Map<String, dynamic> payload) {
    _messageHandler?.call(payload);
  }

  /// Test helper: force connection state for widget tests.
  void debugSetConnectionState(ChatConnectionState state) {
    _setState(state);
  }

  io.Socket? get socket => _socket;
}
