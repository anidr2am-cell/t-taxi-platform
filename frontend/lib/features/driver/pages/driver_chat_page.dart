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
    this.bookingDetailPageBuilder,
  });

  final String bookingNumber;
  final DriverChatApi? api;
  final ChatSocketService? socketService;
  final Widget Function(String bookingNumber)? bookingDetailPageBuilder;

  @override
  State<DriverChatPage> createState() => _DriverChatPageState();
}

class _DriverChatPageState extends State<DriverChatPage> {
  late final DriverChatApi _api = widget.api ?? const DriverChatApi();
  late final ChatRealtimeSession _session;
  final _controller = TextEditingController();
  String _draftText = '';
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleDraftChanged);
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
    _controller.removeListener(_handleDraftChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (!mounted) return;
    if (_draftText == _controller.text) return;
    setState(() {
      _draftText = _controller.text;
    });
  }

  bool get _canSend =>
      _draftText.trim().isNotEmpty &&
      _session.sendingAllowed &&
      !_session.sending &&
      !_session.loading;

  Future<void> _send() async {
    try {
      final text = _controller.text;
      if (text.trim().isEmpty) return;
      if (!_session.sendingAllowed || _session.loading) return;
      setState(() {
        _actionError = null;
      });
      await _session.send(text);
      if (!mounted) return;
      if (!_session.sending && _session.error == null) {
        _controller.clear();
        setState(() {
          _draftText = '';
          _actionError = null;
        });
        return;
      }
      _showSendError(_sessionErrorMessage(context.l10n));
    } catch (err) {
      if (!mounted) return;
      _showSendError(_friendlyErrorMessage(err, context.l10n));
    }
  }

  String? _sessionErrorMessage(AppLocalizations l10n) {
    final err = _actionError ?? _session.error;
    if (err == null) return null;
    if (err.contains('전송 시간이 초과') || err.contains('timed out')) {
      return '전송 시간이 초과되었습니다. 다시 시도해 주세요.';
    }
    if (err.contains('Exception') || err.startsWith('Instance of')) {
      return l10n.t('driver_load_failed');
    }
    return err;
  }

  String _friendlyErrorMessage(Object err, AppLocalizations l10n) {
    final text = err.toString();
    if (text.contains('전송 시간이 초과') || text.contains('timed out')) {
      return '전송 시간이 초과되었습니다. 다시 시도해 주세요.';
    }
    if (text.contains('Exception') || text.startsWith('Instance of')) {
      return l10n.t('driver_load_failed');
    }
    return text;
  }

  void _showSendError(String? message) {
    if (!mounted || message == null) return;
    setState(() {
      _actionError = message;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openBookingDetail() {
    final builder = widget.bookingDetailPageBuilder;
    if (builder == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => builder(widget.bookingNumber)));
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
              title: context.l10n
                  .t('reservation_number')
                  .replaceAll('No.', '')
                  .trim(),
              subtitle: widget.bookingNumber,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('driver_chat_booking_detail_link'),
                onPressed: widget.bookingDetailPageBuilder == null
                    ? null
                    : _openBookingDetail,
                icon: const Icon(Icons.confirmation_number_outlined),
                label: Text(
                  '${l10n.t('reservation_number')} ${widget.bookingNumber}',
                ),
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
                      final rawItem = _session.messages[index];
                      final item = rawItem is Map
                          ? Map<String, dynamic>.from(rawItem)
                          : <String, dynamic>{};
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
                    key: const Key('driver_chat_message_input'),
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
                  key: const Key('driver_chat_send_button'),
                  onPressed: _canSend ? _send : null,
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
