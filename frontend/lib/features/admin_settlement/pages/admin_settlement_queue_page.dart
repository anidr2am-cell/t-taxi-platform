import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_settlement_api_service.dart';

class AdminSettlementQueuePage extends StatefulWidget {
  const AdminSettlementQueuePage({super.key, this.api});

  final AdminSettlementApiService? api;

  @override
  State<AdminSettlementQueuePage> createState() => _AdminSettlementQueuePageState();
}

class _AdminSettlementQueuePageState extends State<AdminSettlementQueuePage> {
  late final AdminSettlementApiService _api = widget.api ?? const AdminSettlementApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  String? _statusFilter;

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
      final data = await _api.listSettlements(status: _statusFilter);
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppUi.adminFilterBar(
          children: [
            DropdownButton<String?>(
              value: _statusFilter,
              hint: const Text('Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All')),
                DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                DropdownMenuItem(value: 'RECEIPT_SUBMITTED', child: Text('Receipt submitted')),
                DropdownMenuItem(value: 'OVERDUE', child: Text('Overdue')),
                DropdownMenuItem(value: 'APPROVED', child: Text('Approved')),
                DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
              ],
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _load();
              },
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        Expanded(
          child: _loading
              ? AppUi.loadingState()
              : _error != null
                  ? AppUi.errorState(message: _error!, onRetry: _load, retryLabel: context.l10n.t('admin_dispatch_retry'))
                  : _items.isEmpty
                      ? AppUi.emptyState(
                          title: 'No settlements',
                          icon: Icons.receipt_long_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: AppUi.pagePadding(context),
                            itemCount: _items.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: AppTokens.spaceSm),
                            itemBuilder: (context, index) {
                              final item = Map<String, dynamic>.from(_items[index] as Map);
                              final status = item['commissionStatus'] as String? ?? '';
                              return AppUi.adminQueueCard(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminSettlementDetailPage(
                                      bookingNumber: item['bookingNumber'] as String,
                                      api: _api,
                                      onChanged: _load,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTokens.primaryLight,
                                        borderRadius: AppTokens.borderRadiusSm,
                                      ),
                                      child: const Icon(
                                        Icons.receipt_long_outlined,
                                        color: AppTokens.primary,
                                      ),
                                    ),
                                    const SizedBox(width: AppTokens.spaceSm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['bookingNumber'] as String? ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                          Text(
                                            item['driverName'] as String? ?? '',
                                            style: const TextStyle(
                                              color: AppTokens.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (item['dueAt'] != null)
                                            Text(
                                              'Due: ${item['dueAt']}',
                                              style: const TextStyle(
                                                color: AppTokens.textMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${item['commissionAmount']} ${item['currency']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        AppUi.statusBadge(
                                          status,
                                          tone: AppUi.toneForCommissionStatus(status),
                                        ),
                                      ],
                                    ),
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

class AdminSettlementDetailPage extends StatefulWidget {
  const AdminSettlementDetailPage({
    super.key,
    required this.bookingNumber,
    required this.api,
    required this.onChanged,
  });

  final String bookingNumber;
  final AdminSettlementApiService api;
  final VoidCallback onChanged;

  @override
  State<AdminSettlementDetailPage> createState() => _AdminSettlementDetailPageState();
}

class _AdminSettlementDetailPageState extends State<AdminSettlementDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  bool _submitting = false;
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

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
      final detail = await widget.api.getSettlement(widget.bookingNumber);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  Future<void> _approve() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.api.approve(widget.bookingNumber);
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reject() async {
    if (_submitting || _reasonController.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.api.reject(widget.bookingNumber, _reasonController.text.trim());
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _detail?['commissionStatus'] as String? ?? '';
    final canReview = status == 'RECEIPT_SUBMITTED';

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      body: _loading
          ? AppUi.loadingState()
          : _error != null
              ? AppUi.errorState(message: _error!, onRetry: _load, retryLabel: 'Retry')
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
                                  '${_detail?['commissionAmount']} ${_detail?['currency']}',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: AppTokens.primaryDark,
                                  ),
                                ),
                              ),
                              AppUi.statusBadge(
                                status,
                                tone: AppUi.toneForCommissionStatus(status),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          Text('Status: $status', style: const TextStyle(fontSize: 18)),
                          if (_detail?['dueAt'] != null)
                            Text('Due: ${_detail?['dueAt']}'),
                          if (_detail?['receiptUrl'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                              child: Text('Receipt on file'),
                            ),
                        ],
                      ),
                    ),
                    if (canReview) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      AppUi.adminDetailSection(
                        context: context,
                        title: 'Review receipt',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: _submitting ? null : _approve,
                                child: const Text('Approve'),
                              ),
                            ),
                            const SizedBox(height: AppTokens.spaceMd),
                            TextField(
                              controller: _reasonController,
                              decoration: const InputDecoration(
                                labelText: 'Rejection reason',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: AppTokens.spaceSm),
                            SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _submitting ? null : _reject,
                                child: const Text('Reject'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
