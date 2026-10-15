import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../driver/utils/driver_backend_datetime.dart';
import '../services/admin_notification_api_service.dart';

class AdminEmailReviewPage extends StatefulWidget {
  const AdminEmailReviewPage({
    super.key,
    this.api = const AdminNotificationApiService(),
  });
  final AdminNotificationApiService api;
  @override
  State<AdminEmailReviewPage> createState() => _AdminEmailReviewPageState();
}

class _AdminEmailReviewPageState extends State<AdminEmailReviewPage> {
  bool _loading = true, _handled = false, _busy = false;
  String? _error;
  int _page = 1;
  bool _hasMore = false;
  List<Map<String, dynamic>> _items = [];
  String t(String key) => context.l10n.t('admin_email_$key');
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
      final result = await widget.api.listEmailReviews(
        includeHandled: _handled,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        _hasMore = result['hasMore'] == true;
        _items = (result['items'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _error = t('error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Map<String, dynamic> row, String action) async {
    if (_busy) return;
    String reason = '';
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(t(action)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    action == 'RETRY_APPROVED'
                        ? 'confirm_retry'
                        : 'confirm_record',
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  maxLines: 3,
                  maxLength: 1000,
                  onChanged: (v) {
                    reason = v;
                    setDialog(() {});
                  },
                  decoration: InputDecoration(labelText: t('reason')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: reason.trim().length < 3
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text(t('confirm')),
            ),
          ],
        ),
      ),
    );
    final note = reason.trim();
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.reviewEmail(
        (row['deliveryId'] as num).toInt(),
        action: action,
        reason: note,
        expectedAttemptId: (row['attemptId'] as num?)?.toInt(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              action == 'RETRY_APPROVED'
                  ? (result['outcome'] == 'ACCEPTED' && result['trackingSaved'] != false
                        ? 'accepted'
                        : 'check_again')
                  : 'recorded',
            ),
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = t('blocked'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history(Map<String, dynamic> row) async {
    try {
      final result = await widget.api.emailHistory(
        (row['deliveryId'] as num).toInt(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('history')),
          content: SizedBox(
            width: AppTokens.maxContentWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final a in result['attempts'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                      child: SelectableText(
                        '${t('trace')}: ${a['trace_id']}\n${t('message_id')}: ${a['message_id']}\n${t('outcome_${a['outcome']}')}\n${formatBackendServiceDateTimeBangkok(a['started_at']?.toString()) ?? ''}\n${a['error_code'] ?? ''} ${a['smtp_command'] ?? ''} ${a['smtp_response_code'] ?? ''}',
                      ),
                    ),
                  for (final r in result['reviews'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                      child: Text(
                        '${t(r['action'] as String)} · ${r['actor_user_id']}\n${formatBackendServiceDateTimeBangkok(r['created_at']?.toString()) ?? ''}\n${r['reason']}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = t('error'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('title'))),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('notice')),
              Wrap(
                spacing: AppTokens.spaceSm,
                children: [
                  FilterChip(
                    label: Text(t('include_handled')),
                    selected: _handled,
                    onSelected: _busy
                        ? null
                        : (v) {
                            setState(() {
                              _handled = v;
                              _page = 1;
                            });
                            _load();
                          },
                  ),
                  IconButton(
                    tooltip: t('previous'),
                    onPressed: _busy || _page == 1
                        ? null
                        : () {
                            _page--;
                            _load();
                          },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$_page'),
                  IconButton(
                    tooltip: t('next'),
                    onPressed: _busy || !_hasMore
                        ? null
                        : () {
                            _page++;
                            _load();
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppTokens.error)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? Center(child: Text(t('empty')))
              : ListView.builder(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  itemCount: _items.length,
                  itemBuilder: (ctx, index) {
                    final row = _items[index];
                    final outcome = row['outcome'] == 'SENDING'
                        ? 'UNKNOWN'
                        : row['outcome']?.toString() ?? 'UNKNOWN';
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      decoration: AppTokens.cardDecorationFlat(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            '${row['bookingNumber'] ?? ''} · ${t('type_${row['notificationType']}')}',
                          ),
                          Text(
                            t('outcome_$outcome'),
                            style: const TextStyle(color: AppTokens.warning),
                          ),
                          Text(
                            '${t('time')}: ${formatBackendServiceDateTimeBangkok(row['updatedAt']?.toString()) ?? ''}',
                          ),
                          if (row['traceId'] != null)
                            SelectableText('${t('trace')}: ${row['traceId']}'),
                          if (row['messageId'] != null)
                            SelectableText(
                              '${t('message_id')}: ${row['messageId']}',
                            ),
                          if (row['lastError'] != null)
                            SelectableText(row['lastError'].toString()),
                          if (row['reviewAction'] != null)
                            Text(
                              '${t(row['reviewAction'] as String)} · ${row['reviewerId']}\n${row['reviewReason'] ?? ''}',
                            ),
                          const SizedBox(height: AppTokens.spaceSm),
                          Wrap(
                            spacing: AppTokens.spaceSm,
                            runSpacing: AppTokens.spaceSm,
                            children: [
                              OutlinedButton(
                                onPressed: _busy ? null : () => _history(row),
                                child: Text(t('history')),
                              ),
                              FilledButton(
                                onPressed: !_busy && row['recoverable'] == true
                                    ? () => _act(row, 'RETRY_APPROVED')
                                    : null,
                                child: Text(t('RETRY_APPROVED')),
                              ),
                              for (final action in [
                                'ACCEPTED_CONFIRMED',
                                'HANDLED_EXTERNALLY',
                                'KEEP_BLOCKED',
                              ])
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _act(row, action),
                                  child: Text(t(action)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
