import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';

class PlaceSearchField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final String languageCode;
  final ValueChanged<Map<String, String>> onSelected;

  const PlaceSearchField({
    super.key,
    required this.label,
    this.initialValue,
    required this.languageCode,
    required this.onSelected,
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) _controller.text = widget.initialValue!;
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService().placesAutocomplete(query, widget.languageCode);
      final predictions = result['predictions'] as List? ?? [];
      setState(() {
        _suggestions = predictions.map((p) => Map<String, dynamic>.from(p as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectPlace(String placeId, String description) async {
    _controller.text = description;
    setState(() => _suggestions = []);
    try {
      final result = await ApiService().placeDetails(placeId, widget.languageCode);
      final resultData = result['result'] as Map<String, dynamic>?;
      final address = resultData?['formatted_address'] as String? ?? description;
      widget.onSelected({'placeId': placeId, 'address': address});
    } catch (_) {
      widget.onSelected({'placeId': placeId, 'address': description});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: context.l10n.t('search_place'),
            suffixIcon: _loading ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ) : null,
          ),
          onChanged: _search,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final item = _suggestions[index];
                return ListTile(
                  title: Text(item['description'] as String? ?? ''),
                  onTap: () => _selectPlace(
                    item['place_id'] as String,
                    item['description'] as String,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class CounterRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  const CounterRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class ChatPanel extends StatefulWidget {
  final String roomId;
  final String senderRole;
  final String senderName;

  const ChatPanel({
    super.key,
    required this.roomId,
    required this.senderRole,
    required this.senderName,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _socketService = SocketService();
  final _messageController = TextEditingController();
  final _messages = <Map<String, dynamic>>[];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final socket = _socketService.connect();

    socket.on('message_history', (data) {
      setState(() {
        _messages.clear();
        _messages.addAll((data as List).map((e) => Map<String, dynamic>.from(e as Map)));
      });
      _scrollToBottom();
    });

    socket.on('new_message', (data) {
      setState(() => _messages.add(Map<String, dynamic>.from(data as Map)));
      _scrollToBottom();
    });

    _socketService.joinRoom(widget.roomId, widget.senderRole, widget.senderName);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _socketService.sendMessage(
      roomId: widget.roomId,
      message: text,
      senderRole: widget.senderRole,
      senderName: widget.senderName,
    );
    _messageController.clear();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isMe = msg['sender_role'] == widget.senderRole;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe)
                        Text(
                          msg['sender_name'] as String? ?? '',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      Text(
                        msg['message'] as String? ?? '',
                        style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                      ),
                      Text(
                        _formatTime(msg['created_at']),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: l10n.t('type_message'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                onPressed: _send,
                icon: const Icon(Icons.send, color: AppTheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    final str = createdAt.toString();
    if (str.length >= 16) return str.substring(11, 16);
    return str;
  }
}
