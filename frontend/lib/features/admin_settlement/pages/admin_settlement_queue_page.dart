import 'package:flutter/material.dart';

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
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
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
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(child: Text('No settlements'))
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = Map<String, dynamic>.from(_items[index] as Map);
                              return ListTile(
                                title: Text(item['bookingNumber'] as String? ?? ''),
                                subtitle: Text(
                                  '${item['driverName'] ?? ''} · ${item['commissionStatus']}',
                                ),
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
                              );
                            },
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
        _error = err.toString();
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Status: $status'),
                      Text('Amount: ${_detail?['commissionAmount']} ${_detail?['currency']}'),
                      if (_detail?['receiptUrl'] != null)
                        Text('Receipt: ${_detail?['receiptUrl']}'),
                      const SizedBox(height: 16),
                      if (canReview) ...[
                        ElevatedButton(
                          onPressed: _submitting ? null : _approve,
                          child: const Text('Approve'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reasonController,
                          decoration: const InputDecoration(
                            labelText: 'Rejection reason',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _submitting ? null : _reject,
                          child: const Text('Reject'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
