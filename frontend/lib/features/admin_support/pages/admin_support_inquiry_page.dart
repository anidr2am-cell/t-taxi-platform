import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/browser_download.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_support_api_service.dart';

class AdminSupportInquiryPage extends StatefulWidget {
  const AdminSupportInquiryPage({super.key, this.api});

  final AdminSupportApiService? api;

  @override
  State<AdminSupportInquiryPage> createState() =>
      _AdminSupportInquiryPageState();
}

class _AdminSupportInquiryPageState extends State<AdminSupportInquiryPage> {
  late final AdminSupportApiService _api =
      widget.api ?? const AdminSupportApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  String? _statusFilter;
  final _searchController = TextEditingController();

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
      final data = await _api.listInquiries(
        status: _statusFilter,
        search: _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
      });
    }
  }

  void _openDetail(int id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminSupportInquiryDetailPage(id: id, api: _api),
      ),
    ).then((_) => _load());
  }

  String _statusLabel(BuildContext context, String status) {
    return context.l10n.t('admin_support_status_${status.toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Column(
        children: [
          AppUi.adminFilterBar(
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_support_search'),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              DropdownButton<String?>(
                value: _statusFilter,
                hint: Text(l10n.t('admin_support_all_statuses')),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.t('admin_support_all_statuses')),
                  ),
                  for (final status in const [
                    'NEW',
                    'IN_PROGRESS',
                    'RESOLVED',
                    'CLOSED',
                  ])
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(context, status)),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _statusFilter = value);
                  _load();
                },
              ),
              IconButton(
                tooltip: l10n.t('admin_dispatch_refresh'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
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
                    title: l10n.t('admin_support_empty'),
                    icon: Icons.support_agent_outlined,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: AppUi.pagePadding(context),
                      itemCount: _items.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: AppTokens.spaceSm),
                      itemBuilder: (context, index) {
                        final item = Map<String, dynamic>.from(
                          _items[index] as Map,
                        );
                        final status = item['status'] as String? ?? 'NEW';
                        final customer =
                            [
                                  item['customerName'],
                                  item['customerPhone'],
                                  item['kakaoId'],
                                  item['lineId'],
                                ]
                                .whereType<String>()
                                .where((value) => value.isNotEmpty)
                                .join(' / ');
                        return AppUi.adminQueueCard(
                          onTap: () => _openDetail(item['id'] as int),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.support_agent_outlined,
                                color: AppTokens.primary,
                              ),
                              const SizedBox(width: AppTokens.spaceSm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['publicId'] as String? ?? '-',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (item['latestMessagePreview']
                                              as String?) ??
                                          (item['messagePreview'] as String?) ??
                                          '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (customer.isNotEmpty)
                                      Text(
                                        customer,
                                        style: const TextStyle(
                                          color: AppTokens.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    Text(
                                      '${l10n.t('admin_support_attachments')}: ${item['attachmentCount'] ?? 0} · ${item['createdAt'] ?? ''}',
                                      style: const TextStyle(
                                        color: AppTokens.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AppUi.statusBadge(_statusLabel(context, status)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminSupportInquiryDetailPage extends StatefulWidget {
  const AdminSupportInquiryDetailPage({
    super.key,
    required this.id,
    required this.api,
  });

  final int id;
  final AdminSupportApiService api;

  @override
  State<AdminSupportInquiryDetailPage> createState() =>
      _AdminSupportInquiryDetailPageState();
}

class _AdminSupportInquiryDetailPageState
    extends State<AdminSupportInquiryDetailPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _detail;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.getInquiry(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String status) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final detail = await widget.api.updateStatus(widget.id, status);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _submitting = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _submitting = false;
      });
    }
  }

  Future<void> _sendReply() async {
    if (_submitting) return;
    final message = _replyController.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final detail = await widget.api.sendReply(widget.id, message);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _replyController.clear();
        _submitting = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('admin_support_reply_failed'),
        );
        _submitting = false;
      });
    }
  }

  String _statusLabel(BuildContext context, String status) {
    return context.l10n.t('admin_support_status_${status.toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = _detail;
    final status = detail?['status'] as String? ?? 'NEW';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('admin_support_detail'))),
      body: _loading
          ? AppUi.loadingState()
          : _error != null && detail == null
          ? AppUi.errorState(
              message: _error!,
              onRetry: _load,
              retryLabel: l10n.t('admin_dispatch_retry'),
            )
          : ListView(
              padding: AppUi.pagePadding(context),
              children: [
                AppUi.surfaceCard(
                  backgroundColor: AppTokens.primaryLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              detail?['publicId'] as String? ?? '-',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          AppUi.statusBadge(_statusLabel(context, status)),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      DropdownButton<String>(
                        value: status,
                        onChanged: _submitting || detail == null
                            ? null
                            : (value) {
                                if (value != null) _updateStatus(value);
                              },
                        items: [
                          for (final value in const [
                            'NEW',
                            'IN_PROGRESS',
                            'RESOLVED',
                            'CLOSED',
                          ])
                            DropdownMenuItem(
                              value: value,
                              child: Text(_statusLabel(context, value)),
                            ),
                        ],
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: AppTokens.error),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  child: _ReplyComposer(
                    controller: _replyController,
                    submitting: _submitting,
                    onSend: _sendReply,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  child: _MessageThread(
                    messages: detail?['messages'] as List<dynamic>? ?? const [],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('admin_support_customer'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.summaryRow(
                        label: l10n.t('admin_support_customer_name'),
                        value: detail?['customerName'] as String? ?? '-',
                      ),
                      AppUi.summaryRow(
                        label: l10n.t('admin_support_customer_phone'),
                        value: detail?['customerPhone'] as String? ?? '-',
                      ),
                      AppUi.summaryRow(
                        label: l10n.t('admin_support_customer_kakao'),
                        value: detail?['kakaoId'] as String? ?? '-',
                      ),
                      AppUi.summaryRow(
                        label: l10n.t('admin_support_customer_line'),
                        value: detail?['lineId'] as String? ?? '-',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  child: _AttachmentList(
                    api: widget.api,
                    inquiryId: widget.id,
                    attachments:
                        detail?['attachments'] as List<dynamic>? ?? const [],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MessageThread extends StatelessWidget {
  const _MessageThread({required this.messages});

  final List<dynamic> messages;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (messages.isEmpty) {
      return Text(
        l10n.t('admin_support_empty'),
        style: const TextStyle(color: AppTokens.textMuted),
      );
    }
    return Column(
      key: const Key('admin_support_message_thread'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('admin_support_messages'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        for (final raw in messages)
          _AdminMessageBubble(message: Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

class _AdminMessageBubble extends StatelessWidget {
  const _AdminMessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final sender = message['senderType'] as String? ?? 'SYSTEM';
    final isAdmin = sender == 'ADMIN';
    final isCustomer = sender == 'CUSTOMER';
    final color = isAdmin
        ? AppTokens.primaryLight
        : isCustomer
        ? AppTokens.surfaceMuted
        : AppTokens.warningLight;

    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: isAdmin
            ? const Key('admin_support_admin_message')
            : const Key('admin_support_customer_message'),
        margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
        constraints: const BoxConstraints(maxWidth: 640),
        padding: const EdgeInsets.all(AppTokens.spaceSm),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppTokens.borderRadiusMd,
          border: Border.all(color: AppTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sender,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTokens.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(message['message'] as String? ?? ''),
          ],
        ),
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.submitting,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('admin_support_reply_title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        TextField(
          key: const Key('admin_support_reply_input'),
          controller: controller,
          enabled: !submitting,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.t('admin_support_reply_label'),
            hintText: l10n.t('admin_support_reply_hint'),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('admin_support_send_reply_button'),
            onPressed: submitting ? null : onSend,
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(l10n.t('admin_support_send_reply')),
          ),
        ),
      ],
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({
    required this.api,
    required this.inquiryId,
    required this.attachments,
  });

  final AdminSupportApiService api;
  final int inquiryId;
  final List<dynamic> attachments;

  String _formatSize(dynamic value) {
    final size = value is num ? value.toInt() : int.tryParse('$value');
    if (size == null || size < 0) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _preview(
    BuildContext context,
    Map<String, dynamic> attachment,
  ) async {
    final l10n = context.l10n;
    try {
      final file = await api.fetchAttachment(
        inquiryId: inquiryId,
        attachmentId: attachment['id'] as int,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    attachment['originalFileName'] as String? ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Flexible(
                    child: InteractiveViewer(
                      child: Image.memory(
                        file.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            AppUi.emptyState(
                              title: l10n.t('admin_support_preview_failed'),
                              icon: Icons.broken_image_outlined,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.t('support_close_button')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(
              err,
              fallback: l10n.t('admin_support_preview_failed'),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _download(
    BuildContext context,
    Map<String, dynamic> attachment,
  ) async {
    final l10n = context.l10n;
    try {
      final file = await api.fetchAttachment(
        inquiryId: inquiryId,
        attachmentId: attachment['id'] as int,
        download: true,
      );
      downloadBytes(
        file.bytes,
        attachment['originalFileName'] as String? ?? 'attachment',
        attachment['mimeType'] as String? ?? file.mimeType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('admin_support_download_started'))),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(
              err,
              fallback: l10n.t('admin_support_download_failed'),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (attachments.isEmpty) {
      return AppUi.emptyState(
        title: l10n.t('admin_support_no_attachments'),
        icon: Icons.image_not_supported_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('admin_support_attachments'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        for (final raw in attachments)
          Builder(
            builder: (context) {
              final attachment = Map<String, dynamic>.from(raw as Map);
              final isImage =
                  attachment['isImage'] == true ||
                  (attachment['mimeType'] as String? ?? '').startsWith(
                    'image/',
                  );
              return ListTile(
                key: const Key('admin_support_attachment_item'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isImage ? Icons.image_outlined : Icons.attach_file_outlined,
                ),
                title: Text(attachment['originalFileName'] as String? ?? '-'),
                subtitle: Text(
                  [
                        attachment['mimeType'] as String? ?? '',
                        _formatSize(attachment['fileSize']),
                      ]
                      .where((value) => value.isNotEmpty && value != '-')
                      .join(' · '),
                ),
                trailing: Wrap(
                  spacing: AppTokens.spaceXs,
                  children: [
                    if (isImage)
                      TextButton.icon(
                        key: const Key('admin_support_attachment_preview'),
                        onPressed: () => _preview(context, attachment),
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(l10n.t('admin_support_preview')),
                      ),
                    TextButton.icon(
                      key: const Key('admin_support_attachment_download'),
                      onPressed: () => _download(context, attachment),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(l10n.t('admin_support_download')),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
