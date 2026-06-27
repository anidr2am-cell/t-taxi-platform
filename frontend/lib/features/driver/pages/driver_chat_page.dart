import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/models/chat_connection_state.dart';
import '../../chat/services/chat_realtime_session.dart';
import '../../chat/services/chat_socket_service.dart';
import '../services/driver_chat_api.dart';

class DriverChatPage extends StatefulWidget {
  const DriverChatPage({
    super.key,
    required this.bookingNumber,
    this.api,
    this.socketService,
  });

  final String bookingNumber;
  final DriverChatApi? api;
  final ChatSocketService? socketService;

  @override
  State<DriverChatPage> createState() => _DriverChatPageState();
}

class _DriverChatPageState extends State<DriverChatPage> {
  late final DriverChatApi _api = widget.api ?? const DriverChatApi();
  late final ChatRealtimeSession _session;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _session = ChatRealtimeSession(
      bookingNumber: widget.bookingNumber,
      loadRoom: () => _api.getRoom(widget.bookingNumber),
      loadMessages: () => _api.listMessages(widget.bookingNumber),
      sendRest: ({required String text, required String clientMessageId}) =>
          _api.sendMessage(
            bookingNumber: widget.bookingNumber,
            text: text,
            clientMessageId: clientMessageId,
          ),
      markReadRest: (upToMessageId) => _api.markRead(
        bookingNumber: widget.bookingNumber,
        upToMessageId: upToMessageId,
      ),
      newClientMessageId: DriverChatApi.newClientMessageId,
      loadAccessToken: () async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('driver_access_token');
      },
      socketService: widget.socketService,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _session.start();
  }

  @override
  void dispose() {
    _session.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    await _session.send(text);
    if (!_session.sending && _session.error == null) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat ${widget.bookingNumber}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: _DriverConnectionChip(state: _session.connectionState)),
          ),
          if (_session.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: Chip(label: Text('${_session.unreadCount}'))),
            ),
          IconButton(onPressed: _session.refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_session.loading) const LinearProgressIndicator(),
          if (_session.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_session.error!, style: const TextStyle(color: Colors.red)),
                  ),
                  if (_session.connectionState == ChatConnectionState.error)
                    TextButton(onPressed: _session.retryConnection, child: const Text('Retry')),
                ],
              ),
            ),
          Expanded(
            child: _session.messages.isEmpty && !_session.loading
                ? const Center(child: Text('No messages yet'))
                : ListView.builder(
                    itemCount: _session.messages.length,
                    itemBuilder: (context, index) {
                      final item = _session.messages[index] as Map<String, dynamic>;
                      return ListTile(
                        title: Text(item['senderDisplayName'] as String? ?? 'Participant'),
                        subtitle: Text(item['text'] as String? ?? ''),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: _session.sendingAllowed && !_session.sending,
                    decoration: InputDecoration(
                      hintText: _session.sendingAllowed
                          ? (_session.hasPendingOutbound
                              ? 'Queued — waiting for connection'
                              : 'Message customer/admin')
                          : 'Read-only chat',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _session.sendingAllowed && !_session.sending ? _send : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverConnectionChip extends StatelessWidget {
  const _DriverConnectionChip({required this.state});

  final ChatConnectionState state;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(chatConnectionLabel(state), style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
    );
  }
}
