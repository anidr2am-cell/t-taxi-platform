import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_review_api_service.dart';

class AdminReviewQueuePage extends StatefulWidget {
  const AdminReviewQueuePage({super.key, this.api});

  final AdminReviewApiService? api;

  @override
  State<AdminReviewQueuePage> createState() => _AdminReviewQueuePageState();
}

class _AdminReviewQueuePageState extends State<AdminReviewQueuePage> {
  late final AdminReviewApiService _api = widget.api ?? const AdminReviewApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  String? _statusFilter;
  int? _ratingFilter;
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
      final data = await _api.listReviews(
        status: _statusFilter,
        rating: _ratingFilter,
        search: _searchController.text.trim(),
      );
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

  void _openDetail(int reviewId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminReviewDetailPage(reviewId: reviewId, api: _api),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppUi.adminFilterBar(
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(labelText: 'Search'),
                onSubmitted: (_) => _load(),
              ),
            ),
            DropdownButton<String?>(
              value: _statusFilter,
              hint: const Text('Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All')),
                DropdownMenuItem(value: 'VISIBLE', child: Text('Visible')),
                DropdownMenuItem(value: 'HIDDEN', child: Text('Hidden')),
              ],
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _load();
              },
            ),
            DropdownButton<int?>(
              value: _ratingFilter,
              hint: const Text('Rating'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All ratings')),
                ...List.generate(
                  5,
                  (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} stars')),
                ),
              ],
              onChanged: (v) {
                setState(() => _ratingFilter = v);
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
                  ? AppUi.errorState(
                      message: _error!,
                      onRetry: _load,
                      retryLabel: context.l10n.t('admin_dispatch_retry'),
                    )
                  : _items.isEmpty
                      ? AppUi.emptyState(
                          title: 'No reviews',
                          icon: Icons.rate_review_outlined,
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
                              final status = item['moderationStatus'] as String? ?? '';
                              final rating = item['rating'] as num? ?? 0;
                              return AppUi.adminQueueCard(
                                onTap: () => _openDetail(item['reviewId'] as int),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTokens.warningLight,
                                        borderRadius: AppTokens.borderRadiusSm,
                                      ),
                                      child: Text(
                                        '$rating★',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppTokens.warning,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppTokens.spaceSm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item['bookingNumber']} · ${item['rating']}★',
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                          Text(
                                            '${item['driver']?['displayName'] ?? 'Driver'} · $status',
                                            style: const TextStyle(
                                              color: AppTokens.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AppUi.statusBadge(
                                      status,
                                      tone: AppUi.toneForModerationStatus(status),
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

class AdminReviewDetailPage extends StatefulWidget {
  const AdminReviewDetailPage({
    super.key,
    required this.reviewId,
    required this.api,
  });

  final int reviewId;
  final AdminReviewApiService api;

  @override
  State<AdminReviewDetailPage> createState() => _AdminReviewDetailPageState();
}

class _AdminReviewDetailPageState extends State<AdminReviewDetailPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _detail;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.getReview(widget.reviewId);
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

  Future<void> _hide() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || _submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hide review?'),
        content: const Text('This review will be excluded from driver ratings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hide')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      final detail = await widget.api.hideReview(widget.reviewId, reason);
      setState(() {
        _detail = detail;
        _submitting = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _submitting = false;
      });
    }
  }

  Future<void> _restore() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore review?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      final detail = await widget.api.restoreReview(widget.reviewId);
      setState(() {
        _detail = detail;
        _submitting = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _detail?['moderationStatus'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('Review #${widget.reviewId}')),
      body: _loading
          ? AppUi.loadingState()
          : _error != null && _detail == null
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
                                  'Rating: ${_detail?['rating']} / 5',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              AppUi.statusBadge(
                                status,
                                tone: AppUi.toneForModerationStatus(status),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          Text('Status: $status'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.surfaceCard(
                      child: Text(_detail?['comment'] as String? ?? '(No comment)'),
                    ),
                    if (_detail?['hiddenReason'] != null) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.summaryRow(
                        label: 'Hidden reason',
                        value: _detail?['hiddenReason'] as String,
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    if (status == 'VISIBLE') ...[
                      TextField(
                        controller: _reasonController,
                        decoration: const InputDecoration(labelText: 'Hide reason'),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _hide,
                          child: Text(_submitting ? 'Working...' : 'Hide review'),
                        ),
                      ),
                    ],
                    if (status == 'HIDDEN')
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _restore,
                          child: Text(_submitting ? 'Working...' : 'Restore review'),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTokens.error),
                        ),
                      ),
                  ],
                ),
    );
  }
}
