import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/user_facing_error.dart';
import '../../chat/models/chat_connection_state.dart';
import '../../chat/services/chat_realtime_session.dart';
import '../../chat/services/chat_socket_service.dart';
import '../../chat/widgets/chat_role_badge.dart';
import '../services/booking_chat_api.dart';
import 'booking_review_form.dart';

class BookingChatSection extends StatefulWidget {
  const BookingChatSection({
    super.key,
    required this.bookingNumber,
    this.guestAccessToken,
    this.api,
    this.socketService,
  });

  final String bookingNumber;
  final String? guestAccessToken;
  final BookingChatApi? api;
  final ChatSocketService? socketService;

  @override
  State<BookingChatSection> createState() => _BookingChatSectionState();
}

class _BookingChatSectionState extends State<BookingChatSection> {
  late final BookingChatApi _api = widget.api ?? const BookingChatApi();
  late final ChatRealtimeSession _session;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _session = ChatRealtimeSession(
      bookingNumber: widget.bookingNumber,
      loadRoom: () async {
        final guestToken = await _guestToken();
        return _api.getRoom(
          bookingNumber: widget.bookingNumber,
          guestAccessToken: guestToken,
        );
      },
      loadMessages: () async {
        final guestToken = await _guestToken();
        return _api.listMessages(
          bookingNumber: widget.bookingNumber,
          guestAccessToken: guestToken,
        );
      },
      sendRest:
          ({required String text, required String clientMessageId}) async {
            final guestToken = await _guestToken();
            return _api.sendMessage(
              bookingNumber: widget.bookingNumber,
              text: text,
              clientMessageId: clientMessageId,
              guestAccessToken: guestToken,
            );
          },
      markReadRest: (upToMessageId) async {
        final guestToken = await _guestToken();
        return _api.markRead(
          bookingNumber: widget.bookingNumber,
          upToMessageId: upToMessageId,
          guestAccessToken: guestToken,
        );
      },
      newClientMessageId: BookingChatApi.newClientMessageId,
      loadGuestAccessToken: _guestToken,
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

  Future<String?> _guestToken() async {
    if (widget.guestAccessToken != null &&
        widget.guestAccessToken!.isNotEmpty) {
      return widget.guestAccessToken;
    }
    return const BookingReviewApi().loadGuestToken(widget.bookingNumber);
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
    final l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.t('booking_chat_title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _ConnectionChip(state: _session.connectionState, l10n: l10n),
                if (_session.unreadCount > 0)
                  Chip(
                    label: Text(
                      l10n
                          .t('booking_chat_unread')
                          .replaceAll('{count}', '${_session.unreadCount}'),
                    ),
                  ),
                IconButton(
                  onPressed: _session.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_session.loading) const LinearProgressIndicator(),
            if (_session.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        userFacingError(
                          _session.error!,
                          fallback: l10n.t('ui_load_failed'),
                        ),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    if (_session.connectionState == ChatConnectionState.error)
                      TextButton(
                        onPressed: _session.retryConnection,
                        child: Text(l10n.t('admin_dispatch_retry')),
                      ),
                  ],
                ),
              ),
            if (!_session.loading && _session.messages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.t('booking_chat_empty')),
              ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: _session.messages.length,
                itemBuilder: (context, index) {
                  final item = _session.messages[index] as Map<String, dynamic>;
                  return ListTile(
                    dense: true,
                    title: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChatRoleBadge(message: item, l10n: l10n),
                        Text(
                          item['senderDisplayName'] as String? ??
                              l10n.t('admin_chat_participant'),
                        ),
                      ],
                    ),
                    subtitle: Text(item['text'] as String? ?? ''),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: _session.sendingAllowed && !_session.sending,
                    decoration: InputDecoration(
                      hintText: _session.sendingAllowed
                          ? (_session.hasPendingOutbound
                                ? l10n.t('admin_chat_hint_queued')
                                : l10n.t('booking_chat_hint_type'))
                          : l10n.t('admin_chat_hint_readonly'),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _session.sendingAllowed && !_session.sending
                      ? _send
                      : null,
                  icon: _session.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state, required this.l10n});

  final ChatConnectionState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ChatConnectionState.connected => Colors.green,
      ChatConnectionState.connecting ||
      ChatConnectionState.reconnecting => Colors.orange,
      ChatConnectionState.error => Colors.red,
      ChatConnectionState.offline => Colors.grey,
    };
    return Chip(
      label: Text(
        chatConnectionLabel(state, l10n),
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}
