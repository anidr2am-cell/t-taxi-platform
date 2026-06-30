import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
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
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _metrics == null) {
      return AppUi.loadingState(message: 'Loading dashboard...');
    }
    if (_error != null && _metrics == null) {
      return AppUi.errorState(message: _error!, onRetry: _load);
    }

    final metrics = _metrics!;
    final activeTrips = metrics.bookings.onRoute + metrics.bookings.arrived;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppUi.pagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          AppUi.sectionHeader(
            context,
            title: 'Operations for ${metrics.date}',
            subtitle: '${metrics.timezone} · Last updated ${metrics.updatedAt}',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            AppUi.errorState(message: _error!),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.sectionHeader(
            context,
            title: 'Needs attention',
            subtitle: 'Prioritize unassigned bookings, active trips, and settlement issues.',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppUi.kpiMetricCard(
                label: 'Unassigned',
                value: '${metrics.bookings.unassigned}',
                icon: Icons.person_add_alt,
                tone: AppStatusTone.warning,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.kpiMetricCard(
                label: 'Active trips',
                value: '$activeTrips',
                icon: Icons.route,
                tone: AppStatusTone.info,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.kpiMetricCard(
                label: 'Overdue settlements',
                value: '${metrics.settlements.overdue}',
                icon: Icons.warning_amber_outlined,
                tone: metrics.settlements.overdue > 0 ? AppStatusTone.error : AppStatusTone.neutral,
                onTap: widget.onOpenSettlements,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.sectionHeader(
            context,
            title: 'Operational focus',
            subtitle: 'Tap a row to open the relevant queue.',
          ),
          _FocusTile(
            label: 'Bookings needing assignment',
            value: metrics.bookings.unassigned,
            tone: AppStatusTone.warning,
            onTap: widget.onOpenDispatch,
          ),
          const SizedBox(height: 8),
          _FocusTile(
            label: 'Active trips',
            value: activeTrips,
            tone: AppStatusTone.info,
            onTap: widget.onOpenDispatch,
          ),
          const SizedBox(height: 8),
          _FocusTile(
            label: 'Overdue settlements',
            value: metrics.settlements.overdue,
            tone: metrics.settlements.overdue > 0 ? AppStatusTone.error : AppStatusTone.neutral,
            onTap: widget.onOpenSettlements,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.sectionHeader(
            context,
            title: 'Today\'s bookings',
            subtitle: 'Tap a card to open dispatch.',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppUi.metricCard(
                label: 'Today bookings',
                value: '${metrics.bookings.today}',
                icon: Icons.today,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: 'Assigned',
                value: '${metrics.bookings.assigned}',
                icon: Icons.assignment_ind,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: 'On route',
                value: '${metrics.bookings.onRoute}',
                icon: Icons.route,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: 'Arrived',
                value: '${metrics.bookings.arrived}',
                icon: Icons.pin_drop,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: 'Completed',
                value: '${metrics.bookings.completed}',
                icon: Icons.check_circle,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: 'Cancelled',
                value: '${metrics.bookings.cancelled}',
                icon: Icons.cancel,
                onTap: widget.onOpenDispatch,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.sectionHeader(context, title: 'Fleet & finance'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppUi.metricCard(
                label: 'Online drivers',
                value: '${metrics.drivers.online}',
                icon: Icons.local_taxi,
              ),
              AppUi.metricCard(
                label: 'Pending settlements',
                value: '${metrics.settlements.pending}',
                icon: Icons.receipt_long,
                onTap: widget.onOpenSettlements,
              ),
              AppUi.metricCard(
                label: 'Today revenue',
                value: _money(metrics.revenue.todayBooked, metrics.revenue.currency),
                icon: Icons.payments,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.surfaceMuted,
            child: Text(
              'Completed-trip revenue today: ${_money(metrics.revenue.todayCompleted, metrics.revenue.currency)}',
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _money(num? amount, String currency) {
    if (amount == null) return 'Mixed currencies';
    return '${amount.toStringAsFixed(0)} $currency';
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
  });

  final String label;
  final int value;
  final AppStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          AppUi.statusBadge('$value', tone: tone),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTokens.textMuted, size: 18),
          ],
        ],
      ),
    );
  }
}
