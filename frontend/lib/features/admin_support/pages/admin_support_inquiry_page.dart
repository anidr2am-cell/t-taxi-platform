import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
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
                                  item['customerEmail'],
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
                                      item['messagePreview'] as String? ?? '',
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

  @override
  void initState() {
    super.initState();
    _load();
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
                  child: Text(detail?['message'] as String? ?? ''),
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
                        label: l10n.t('admin_support_customer_email'),
                        value: detail?['customerEmail'] as String? ?? '-',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  child: _AttachmentList(
                    attachments:
                        detail?['attachments'] as List<dynamic>? ?? const [],
                  ),
                ),
              ],
            ),
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({required this.attachments});

  final List<dynamic> attachments;

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
        for (final attachment in attachments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image_outlined),
            title: Text(
              Map<String, dynamic>.from(attachment as Map)['originalFileName']
                      as String? ??
                  '-',
            ),
            subtitle: Text(
              Map<String, dynamic>.from(attachment)['mimeType'] as String? ??
                  '',
            ),
          ),
      ],
    );
  }
}
