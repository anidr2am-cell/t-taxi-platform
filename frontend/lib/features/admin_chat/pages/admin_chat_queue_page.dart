import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/models/chat_connection_state.dart';
import '../../chat/services/chat_realtime_session.dart';
import '../../chat/services/chat_socket_service.dart';
import '../services/admin_chat_api_service.dart';

class AdminChatQueuePage extends StatefulWidget {
  const AdminChatQueuePage({super.key, this.api});

  final AdminChatApiService? api;

  @override
  State<AdminChatQueuePage> createState() => _AdminChatQueuePageState();
}

class _AdminChatQueuePageState extends State<AdminChatQueuePage> {
  late final AdminChatApiService _api = widget.api ?? const AdminChatApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  bool _unreadOnly = false;
  final _searchController = TextEditingController();
  String? _selectedBooking;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.listChats(
        unreadOnly: _unreadOnly,
        search: _searchController.text.trim(),
      );
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openChat(String bookingNumber) async {
    setState(() => _selectedBooking = bookingNumber);
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBooking != null) {
      return AdminChatDetailPage(
        bookingNumber: _selectedBooking!,
        api: _api,
        onBack: () => setState(() => _selectedBooking = null),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(labelText: 'Search booking/customer/driver'),
                  onSubmitted: (_) => _load(),
                ),
              ),
              FilterChip(
                label: const Text('Unread only'),
                selected: _unreadOnly,
                onSelected: (v) {
                  setState(() => _unreadOnly = v);
                  _load();
                },
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(child: Text('No chats found'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index] as Map<String, dynamic>;
                    final unread = item['unreadCount'] as int? ?? 0;
                    return ListTile(
                      title: Text(item['bookingNumber'] as String? ?? ''),
                      subtitle: Text(
                        '${item['customerDisplayName'] ?? ''} · ${item['driverDisplayName'] ?? 'No driver'}',
                      ),
                      trailing: unread > 0 ? Chip(label: Text('$unread')) : null,
                      onTap: () => _openChat(item['bookingNumber'] as String),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class AdminChatDetailPage extends StatefulWidget {
  const AdminChatDetailPage({
    super.key,
    required this.bookingNumber,
    required this.onBack,
    this.api,
    this.socketService,
  });

  final String bookingNumber;
  final VoidCallback onBack;
  final AdminChatApiService? api;
  final ChatSocketService? socketService;

  @override
  State<AdminChatDetailPage> createState() => _AdminChatDetailPageState();
}

class _AdminChatDetailPageState extends State<AdminChatDetailPage> {
  late final AdminChatApiService _api = widget.api ?? const AdminChatApiService();
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
      newClientMessageId: AdminChatApiService.newClientMessageId,
      loadAccessToken: () async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('admin_access_token');
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
    return Column(
      children: [
        ListTile(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          title: Text('Chat ${widget.bookingNumber}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                label: Text(
                  chatConnectionLabel(_session.connectionState),
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(onPressed: _session.refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        if (_session.loading) const LinearProgressIndicator(),
        if (_session.error != null)
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(_session.error!, style: const TextStyle(color: Colors.red)),
                ),
              ),
              if (_session.connectionState == ChatConnectionState.error)
                TextButton(onPressed: _session.retryConnection, child: const Text('Retry')),
            ],
          ),
        Expanded(
          child: ListView.builder(
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
                            : 'Message participants')
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
    );
  }
}
