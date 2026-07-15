import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../chat/models/chat_connection_state.dart';
import '../../chat/services/chat_realtime_session.dart';
import '../../chat/services/chat_socket_service.dart';
import '../../chat/widgets/chat_role_badge.dart';
import '../services/admin_chat_api_service.dart';

const _narrowBreakpoint = 600.0;

String _formatChatTimestamp(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

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

String _friendlyLoadError(Object err, AppLocalizations l10n) {
  if (err is AdminChatApiException) return err.message;
  return l10n.t('admin_chat_load_error');
}

class AdminChatQueuePage extends StatefulWidget {
  const AdminChatQueuePage({super.key, this.api});

  final AdminChatApiService? api;

  @override
  State<AdminChatQueuePage> createState() => _AdminChatQueuePageState();
}

class _AdminChatQueuePageState extends State<AdminChatQueuePage> {
  late final AdminChatApiService _api =
      widget.api ?? const AdminChatApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  bool _unreadOnly = false;
  bool _showArchived = false;
  bool _archiveSubmitting = false;
  final Set<String> _selectedThreads = {};
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
        archived: _showArchived,
      );
      if (!mounted) return;
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _selectedThreads.clear();
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyLoadError(err, context.l10n);
        _loading = false;
      });
    }
  }

  Future<void> _openChat(String bookingNumber) async {
    setState(() => _selectedBooking = bookingNumber);
  }

  void _toggleThreadSelection(String bookingNumber, bool selected) {
    setState(() {
      if (selected) {
        _selectedThreads.add(bookingNumber);
      } else {
        _selectedThreads.remove(bookingNumber);
      }
    });
  }

  Future<void> _archiveSelectedThreads() async {
    if (_selectedThreads.isEmpty || _archiveSubmitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('선택한 채팅을 테스트 데이터로 보관하시겠습니까?'),
        content: const Text(
          '기본 관리자 채팅 목록에서 숨겨지며, 고객/기사 화면에는 새로 열리지 않습니다. 메시지와 예약 기록은 삭제하지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('테스트 채팅 보관'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _archiveSubmitting = true);
    try {
      await _api.archiveThreads(_selectedThreads.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('선택한 채팅을 보관했습니다.')));
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyLoadError(err, context.l10n))),
      );
    } finally {
      if (mounted) setState(() => _archiveSubmitting = false);
    }
  }

  Future<void> _restoreThread(String bookingNumber) async {
    try {
      await _api.restoreThread(bookingNumber);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('보관한 채팅을 복원했습니다.')));
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyLoadError(err, context.l10n))),
      );
    }
  }

  Widget _queueCard(AppLocalizations l10n, Map<String, dynamic> item) {
    final bookingNumber = item['bookingNumber'] as String? ?? '';
    final customer = item['customerDisplayName'] as String? ?? '';
    final driver =
        item['driverDisplayName'] as String? ?? l10n.t('admin_chat_no_driver');
    final unread = item['unreadCount'] as int? ?? 0;
    final lastMessage = item['lastMessageText'] as String?;
    final lastMessageAt = _formatChatTimestamp(
      item['lastMessageAt'] as String?,
    );
    final hasUnread = unread > 0;
    final archived = item['archived'] == true;

    return AppUi.adminQueueCard(
      onTap: () => _openChat(bookingNumber),
      backgroundColor: hasUnread
          ? AppTokens.primaryLight.withValues(alpha: 0.35)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_showArchived)
            Checkbox(
              value: _selectedThreads.contains(bookingNumber),
              onChanged: (value) =>
                  _toggleThreadSelection(bookingNumber, value == true),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasUnread
                  ? AppTokens.primaryLight
                  : AppTokens.surfaceMuted,
              borderRadius: AppTokens.borderRadiusSm,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              color: hasUnread ? AppTokens.primary : AppTokens.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bookingNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (lastMessageAt.isNotEmpty)
                      Text(
                        lastMessageAt,
                        style: const TextStyle(
                          color: AppTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                if (archived) ...[
                  const SizedBox(height: 4),
                  AppUi.statusBadge(
                    'Archived/Test',
                    tone: AppStatusTone.neutral,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '$customer · $driver',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (lastMessage != null && lastMessage.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    lastMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread
                          ? AppTokens.textPrimary
                          : AppTokens.textSecondary,
                      fontWeight: hasUnread
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasUnread) ...[
            const SizedBox(width: AppTokens.spaceSm),
            AppUi.statusBadge(unread.toString(), tone: AppStatusTone.info),
          ],
          if (_showArchived) ...[
            const SizedBox(width: AppTokens.spaceSm),
            OutlinedButton.icon(
              onPressed: () => _restoreThread(bookingNumber),
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('복원'),
            ),
          ],
        ],
      ),
    );
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

    final l10n = context.l10n;
    final narrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
    final searchWidth = narrow
        ? MediaQuery.sizeOf(context).width - (AppTokens.spaceMd * 2)
        : 280.0;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.adminFilterBar(
            children: [
              SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_chat_search'),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              FilterChip(
                label: Text(l10n.t('admin_chat_unread_only')),
                selected: _unreadOnly,
                onSelected: (v) {
                  setState(() => _unreadOnly = v);
                  _load();
                },
              ),
              FilterChip(
                label: const Text('보관한 채팅 보기'),
                selected: _showArchived,
                onSelected: (v) {
                  setState(() {
                    _showArchived = v;
                    _selectedThreads.clear();
                  });
                  _load();
                },
              ),
              if (!_showArchived)
                FilledButton.icon(
                  onPressed: _selectedThreads.isEmpty || _archiveSubmitting
                      ? null
                      : _archiveSelectedThreads,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text('테스트 채팅 보관 (${_selectedThreads.length})'),
                ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: _loading
                ? AppUi.loadingState()
                : _error != null
                ? AppUi.errorState(
                    message: _error!,
                    onRetry: _load,
                    retryLabel: l10n.t('admin_dispatch_retry'),
                  )
                : _items.isEmpty
                ? AppUi.emptyState(
                    title: l10n.t('admin_chat_empty'),
                    icon: Icons.chat_outlined,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: AppUi.pagePadding(context),
                      itemCount: _items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppTokens.spaceSm),
                      itemBuilder: (context, index) {
                        final item = Map<String, dynamic>.from(
                          _items[index] as Map,
                        );
                        return _queueCard(l10n, item);
                      },
                    ),
                  ),
          ),
        ],
      ),
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
  late final AdminChatApiService _api =
      widget.api ?? const AdminChatApiService();
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

  String? _sessionErrorMessage(AppLocalizations l10n) {
    final err = _session.error;
    if (err == null) return null;
    if (err.contains('Exception') || err.startsWith('Instance of')) {
      return l10n.t('admin_chat_load_error');
    }
    return err;
  }

  Widget _messageTile(AppLocalizations l10n, Map<String, dynamic> item) {
    final sender =
        item['senderDisplayName'] as String? ??
        l10n.t('admin_chat_participant');
    final text = item['text'] as String? ?? '';
    final createdAt = _formatChatTimestamp(item['createdAt'] as String?);
    final hidden = item['hidden'] == true;
    final messageId = item['messageId'] as int? ?? 0;

    return AppUi.surfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sender,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (createdAt.isNotEmpty)
                Text(
                  createdAt,
                  style: const TextStyle(
                    color: AppTokens.textMuted,
                    fontSize: 11,
                  ),
                ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleMessageAction(value, messageId),
                itemBuilder: (context) => [
                  if (!hidden)
                    const PopupMenuItem(value: 'hide', child: Text('메시지 숨기기')),
                  if (hidden)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text('메시지 복원'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: AppTokens.spaceXs,
            runSpacing: AppTokens.spaceXs,
            children: [
              ChatRoleBadge(message: item, l10n: l10n),
              if (hidden)
                AppUi.statusBadge('Hidden', tone: AppStatusTone.neutral),
            ],
          ),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _handleMessageAction(String action, int messageId) async {
    if (messageId <= 0) return;
    try {
      if (action == 'hide') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('선택한 메시지를 숨기시겠습니까?'),
            content: const Text('고객과 기사 화면에는 삭제된 메시지로 표시됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('숨기기'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await _api.hideMessage(messageId: messageId);
      } else if (action == 'restore') {
        await _api.restoreMessage(messageId: messageId);
      }
      await _session.refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyLoadError(err, context.l10n))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionError = _sessionErrorMessage(l10n);
    final inputHint = _session.sendingAllowed
        ? (_session.hasPendingOutbound
              ? l10n.t('admin_chat_hint_queued')
              : l10n.t('admin_chat_hint_message'))
        : l10n.t('admin_chat_hint_readonly');

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppUi.pagePadding(context).copyWith(bottom: 0),
            child: AppUi.sectionHeader(
              context,
              title: widget.bookingNumber,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppUi.statusBadge(
                    chatConnectionLabel(_session.connectionState, context.l10n),
                    tone: _toneForConnection(_session.connectionState),
                  ),
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
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
                        child: Text(l10n.t('admin_dispatch_retry')),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _session.messages.isEmpty && !_session.loading
                ? AppUi.emptyState(
                    title: l10n.t('admin_chat_no_messages'),
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
                      return _messageTile(l10n, item);
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
