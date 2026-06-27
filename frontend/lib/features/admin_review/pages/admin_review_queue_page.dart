import 'package:flutter/material.dart';

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
        _error = err.toString();
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
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
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            ElevatedButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? const Center(child: Text('No reviews'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _items.length,
                              separatorBuilder: (_, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = Map<String, dynamic>.from(_items[index] as Map);
                                return ListTile(
                                  title: Text('${item['bookingNumber']} · ${item['rating']}★'),
                                  subtitle: Text(
                                    '${item['driver']?['displayName'] ?? 'Driver'} · ${item['moderationStatus']}',
                                  ),
                                  trailing: Text(item['customerDisplayName'] as String? ?? ''),
                                  onTap: () => _openDetail(item['reviewId'] as int),
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
        _error = err.toString();
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
        _error = err.toString();
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
        _error = err.toString();
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _detail == null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Rating: ${_detail?['rating']} / 5', style: const TextStyle(fontSize: 18)),
                      Text('Status: $status'),
                      const SizedBox(height: 8),
                      Text(_detail?['comment'] as String? ?? '(No comment)'),
                      if (_detail?['hiddenReason'] != null)
                        Text('Hidden reason: ${_detail?['hiddenReason']}'),
                      const SizedBox(height: 16),
                      if (status == 'VISIBLE') ...[
                        TextField(
                          controller: _reasonController,
                          decoration: const InputDecoration(labelText: 'Hide reason'),
                        ),
                        ElevatedButton(
                          onPressed: _submitting ? null : _hide,
                          child: Text(_submitting ? 'Working...' : 'Hide review'),
                        ),
                      ],
                      if (status == 'HIDDEN')
                        ElevatedButton(
                          onPressed: _submitting ? null : _restore,
                          child: Text(_submitting ? 'Working...' : 'Restore review'),
                        ),
                      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ),
                ),
    );
  }
}
