import '../models/chat_connection_state.dart';
import 'chat_message_list.dart';
import 'chat_socket_service.dart';

typedef ChatLoadRoom = Future<Map<String, dynamic>> Function();
typedef ChatLoadMessages = Future<List<dynamic>> Function();
typedef ChatSendRest =
    Future<Map<String, dynamic>> Function({
      required String text,
      required String clientMessageId,
    });
typedef ChatMarkReadRest =
    Future<Map<String, dynamic>> Function(int upToMessageId);
typedef ChatNewClientMessageId = String Function();
typedef ChatAccessTokenLoader = Future<String?> Function();

/// REST history + Socket.IO realtime for one booking chat room.
class ChatRealtimeSession {
  ChatRealtimeSession({
    required this.bookingNumber,
    required this.loadRoom,
    required this.loadMessages,
    required this.sendRest,
    required this.markReadRest,
    required this.newClientMessageId,
    this.loadAccessToken,
    this.loadGuestAccessToken,
    ChatSocketService? socketService,
    this.onChanged,
  }) : _socket = socketService ?? ChatSocketService() {
    _socket.onConnectionStateChanged = _notify;
    _socket.onReconnected = _handleReconnected;
  }

  final String bookingNumber;
  final ChatLoadRoom loadRoom;
  final ChatLoadMessages loadMessages;
  final ChatSendRest sendRest;
  final ChatMarkReadRest markReadRest;
  final ChatNewClientMessageId newClientMessageId;
  final ChatAccessTokenLoader? loadAccessToken;
  final ChatAccessTokenLoader? loadGuestAccessToken;
  final void Function()? onChanged;

  final ChatSocketService _socket;

  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _sendingAllowed = true;
  int _unreadCount = 0;
  List<dynamic> _messages = [];
  String? _pendingClientMessageId;
  String? _pendingOutboundText;
  int? _lastMarkedReadId;
  int? _roomId;
  bool _disposed = false;

  ChatSocketService get socketService => _socket;

  bool get loading => _loading;
  bool get sending => _sending;
  String? get error => _error;
  bool get sendingAllowed => _sendingAllowed;
  int get unreadCount => _unreadCount;
  List<dynamic> get messages => List.unmodifiable(_messages);
  ChatConnectionState get connectionState =>
      _socket.connectionState == ChatConnectionState.error &&
          !_loading &&
          _error == null
      ? ChatConnectionState.offline
      : _socket.connectionState;
  bool get hasPendingOutbound => _pendingOutboundText != null;

  Future<void> start() async {
    await _loadHistory(joinSocket: true);
  }

  Future<void> refresh() => _loadHistory(joinSocket: false);

  Future<void> retryConnection() async {
    _error = null;
    _notify();
    await _connectSocket();
    await _loadHistory(joinSocket: true);
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending || !_sendingAllowed) return;

    await _sendInternal(trimmed);
  }

  void dispose() {
    _disposed = true;
    _socket.onConnectionStateChanged = null;
    _socket.onReconnected = null;
    _socket.disconnect();
  }

  void _notify() {
    if (!_disposed) onChanged?.call();
  }

  Future<void> _loadHistory({required bool joinSocket}) async {
    _loading = true;
    _error = null;
    _notify();
    try {
      if (joinSocket) {
        await _connectSocket();
      }
      final room = await loadRoom();
      final messages = await loadMessages();
      _sendingAllowed = room['sendingAllowed'] as bool? ?? true;
      _unreadCount = room['unreadCount'] as int? ?? 0;
      _roomId = room['roomId'] as int?;
      _messages = ChatMessageList.mergeHistory(_messages, messages);
      _loading = false;
      _notify();
      await _markVisibleRead();
      if (joinSocket && _socket.isConnected) {
        _socket.joinRoom(bookingNumber);
      }
      await _flushPendingOutbound();
    } catch (err) {
      _loading = false;
      _error = err.toString();
      _notify();
    }
  }

  Future<void> _connectSocket() async {
    final accessToken = loadAccessToken != null
        ? await loadAccessToken!()
        : null;
    final guestToken = loadGuestAccessToken != null
        ? await loadGuestAccessToken!()
        : null;
    _socket.setHandlers(
      onMessage: _handleSocketMessage,
      onReadUpdated: _handleReadUpdated,
      onError: (payload) {
        final code = payload['code'] as String? ?? '';
        if (code == 'CHAT_NOT_ACCESSIBLE' || code == 'CHAT_READ_ONLY') {
          _sendingAllowed = false;
        }
        _error = payload['message'] as String? ?? 'Chat error';
        _notify();
      },
    );
    _socket.connect(accessToken: accessToken, guestAccessToken: guestToken);
    _notify();
  }

  Future<void> _handleReconnected() async {
    await _loadHistory(joinSocket: true);
  }

  void _handleSocketMessage(Map<String, dynamic> payload) {
    if (payload['bookingNumber'] != bookingNumber) return;
    final roomId = payload['roomId'] as int?;
    if (_roomId != null && roomId != null && roomId != _roomId) return;

    final message = payload['message'];
    if (message is! Map) return;
    final map = Map<String, dynamic>.from(message);
    _messages = ChatMessageList.upsert(_messages, map);
    _notify();
    _markVisibleRead();
  }

  void _handleReadUpdated(Map<String, dynamic> payload) {
    if (payload['bookingNumber'] != bookingNumber) return;
    final unread = payload['unreadCount'];
    if (unread is int) {
      _unreadCount = unread;
      _notify();
    }
  }

  Future<void> _sendInternal(String text) async {
    final clientMessageId = _pendingClientMessageId ?? newClientMessageId();
    _pendingClientMessageId = clientMessageId;
    _sending = true;
    _error = null;
    _notify();

    try {
      final optimistic = {
        'messageId': null,
        'clientMessageId': clientMessageId,
        'senderDisplayName': 'You',
        'text': text,
        'createdAt': DateTime.now().toIso8601String(),
      };
      _messages = ChatMessageList.upsert(_messages, optimistic);
      _notify();

      final message = await sendRest(
        text: text,
        clientMessageId: clientMessageId,
      );
      _messages = ChatMessageList.upsert(_messages, message);
      _pendingClientMessageId = null;
      _pendingOutboundText = null;
      _sending = false;
      _notify();
      await _markVisibleRead();
    } catch (err) {
      _messages = _messages
          .where(
            (m) =>
                (m as Map)['clientMessageId'] != clientMessageId ||
                m['messageId'] != null,
          )
          .toList();
      _pendingClientMessageId = clientMessageId;
      _pendingOutboundText = text;
      _sending = false;
      _error = err.toString();
      _notify();
    }
  }

  Future<void> _flushPendingOutbound() async {
    if (_pendingOutboundText == null ||
        _socket.connectionState != ChatConnectionState.connected ||
        _sending) {
      return;
    }
    final text = _pendingOutboundText!;
    _pendingOutboundText = null;
    await _sendInternal(text);
  }

  Future<void> _markVisibleRead() async {
    if (_messages.isEmpty) return;
    final last = _messages.last as Map<String, dynamic>;
    final lastId = last['messageId'] as int?;
    if (lastId == null || lastId == _lastMarkedReadId) return;
    _lastMarkedReadId = lastId;
    try {
      final result = await markReadRest(lastId);
      _unreadCount = result['unreadCount'] as int? ?? _unreadCount;
      if (_socket.isConnected) {
        _socket.markRead(bookingNumber: bookingNumber, upToMessageId: lastId);
      }
      _notify();
    } catch (_) {
      _lastMarkedReadId = null;
    }
  }
}
