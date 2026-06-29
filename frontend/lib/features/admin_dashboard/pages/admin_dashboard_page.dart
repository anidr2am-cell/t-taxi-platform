import 'package:flutter/material.dart';

import '../models/admin_dashboard_metrics.dart';
import '../services/admin_dashboard_api_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    super.key,
    this.api = const AdminDashboardApiService(),
    this.onOpenDispatch,
    this.onOpenSettlements,
  });

  final AdminDashboardApiService api;
  final VoidCallback? onOpenDispatch;
  final VoidCallback? onOpenSettlements;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  AdminDashboardMetrics? _metrics;
  bool _loading = true;
  String? _error;

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
      final metrics = await widget.api.getMetrics();
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _metrics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _metrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final metrics = _metrics!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Operations for ${metrics.date} (${metrics.timezone})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text('Last updated: ${metrics.updatedAt}'),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard('Today bookings', metrics.bookings.today, Icons.today, widget.onOpenDispatch),
              _MetricCard('Unassigned', metrics.bookings.unassigned, Icons.person_add_alt, widget.onOpenDispatch),
              _MetricCard('Assigned', metrics.bookings.assigned, Icons.assignment_ind, widget.onOpenDispatch),
              _MetricCard('On route', metrics.bookings.onRoute, Icons.route, widget.onOpenDispatch),
              _MetricCard('Arrived', metrics.bookings.arrived, Icons.pin_drop, widget.onOpenDispatch),
              _MetricCard('Completed', metrics.bookings.completed, Icons.check_circle, widget.onOpenDispatch),
              _MetricCard('Cancelled', metrics.bookings.cancelled, Icons.cancel, widget.onOpenDispatch),
              _MetricCard('Online drivers', metrics.drivers.online, Icons.local_taxi, null),
              _MetricCard(
                'Pending settlements',
                metrics.settlements.pending,
                Icons.receipt_long,
                widget.onOpenSettlements,
              ),
              _MetricCard(
                'Today revenue',
                _money(metrics.revenue.todayBooked, metrics.revenue.currency),
                Icons.payments,
                null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Operational focus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _FocusTile(
            label: 'Bookings needing assignment',
            value: metrics.bookings.unassigned,
            onTap: widget.onOpenDispatch,
          ),
          _FocusTile(
            label: 'Active trips',
            value: metrics.bookings.onRoute + metrics.bookings.arrived,
            onTap: widget.onOpenDispatch,
          ),
          _FocusTile(
            label: 'Overdue settlements',
            value: metrics.settlements.overdue,
            onTap: widget.onOpenSettlements,
          ),
          const SizedBox(height: 8),
          Text(
            'Completed-trip revenue today: ${_money(metrics.revenue.todayCompleted, metrics.revenue.currency)}',
          ),
        ],
      ),
    );
  }

  String _money(num? amount, String currency) {
    if (amount == null) return 'Mixed currencies';
    return '${amount.toStringAsFixed(0)} $currency';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, this.onTap);

  final String label;
  final Object value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text('$value'),
      onTap: onTap,
    );
  }
}
