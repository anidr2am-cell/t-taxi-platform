import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../chat/models/chat_connection_state.dart';
import '../../chat/services/chat_realtime_session.dart';
import '../../chat/services/chat_socket_service.dart';
import '../services/driver_chat_api.dart';

AppStatusTone _toneForConnection(ChatConnectionState state) {
  switch (state) {
    case ChatConnectionState.connected:
      return AppStatusTone.success;
    case ChatConnectionState.connecting:
    case ChatConnectionState.reconnecting:
      return AppStatusTone.warning;
    case ChatConnectionState.error:
      return AppStatusTone.error;
    case ChatConnectionState.offline:
      return AppStatusTone.neutral;
  }
}

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

  String? _sessionErrorMessage(AppLocalizations l10n) {
    final err = _session.error;
    if (err == null) return null;
    if (err.contains('Exception') || err.startsWith('Instance of')) {
      return l10n.t('driver_load_failed');
    }
    return err;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionError = _sessionErrorMessage(l10n);
    final inputHint = _session.sendingAllowed
        ? (_session.hasPendingOutbound
              ? l10n.t('driver_chat_queued')
              : l10n.t('driver_chat_hint_message'))
        : l10n.t('driver_chat_readonly');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_message_customer'))),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppUi.pagePadding(context).copyWith(bottom: 0),
            child: AppUi.sectionHeader(
              context,
              title: widget.bookingNumber,
              trailing: Wrap(
                spacing: AppTokens.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppUi.statusBadge(
                    chatConnectionLabel(_session.connectionState, context.l10n),
                    tone: _toneForConnection(_session.connectionState),
                  ),
                  if (_session.unreadCount > 0)
                    AppUi.statusBadge(
                      '${_session.unreadCount}',
                      tone: AppStatusTone.info,
                    ),
                  IconButton(
                    onPressed: _session.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          if (_session.loading) const LinearProgressIndicator(),
          if (sessionError != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd,
              ),
              child: AppUi.surfaceCard(
                backgroundColor: AppTokens.errorLight,
                padding: const EdgeInsets.all(AppTokens.spaceSm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sessionError,
                        style: const TextStyle(
                          color: AppTokens.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (_session.connectionState == ChatConnectionState.error)
                      TextButton(
                        onPressed: _session.retryConnection,
                        child: Text(l10n.t('driver_retry')),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _session.messages.isEmpty && !_session.loading
                ? AppUi.emptyState(
                    title: l10n.t('driver_chat_no_messages'),
                    icon: Icons.forum_outlined,
                  )
                : ListView.separated(
                    padding: AppUi.pagePadding(context),
                    itemCount: _session.messages.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppTokens.spaceSm),
                    itemBuilder: (context, index) {
                      final item = Map<String, dynamic>.from(
                        _session.messages[index] as Map,
                      );
                      final sender =
                          item['senderDisplayName'] as String? ??
                          l10n.t('driver_chat_participant');
                      final text = item['text'] as String? ?? '';
                      return AppUi.surfaceCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceMd,
                          vertical: AppTokens.spaceSm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sender,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(text, style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: AppUi.pagePadding(context),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: _session.sendingAllowed && !_session.sending,
                    decoration: InputDecoration(
                      hintText: inputHint,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                FilledButton(
                  onPressed: _session.sendingAllowed && !_session.sending
                      ? _send
                      : null,
                  child: _session.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
