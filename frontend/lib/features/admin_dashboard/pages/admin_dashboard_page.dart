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
    final l10n = context.l10n;

    if (_loading && _metrics == null) {
      return AppUi.loadingState(message: l10n.t('admin_dashboard_loading'));
    }
    if (_error != null && _metrics == null) {
      return AppUi.errorState(
        message: _error!,
        onRetry: _load,
        retryLabel: l10n.t('admin_dispatch_retry'),
      );
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
            title: l10n.t('admin_dashboard_operations').replaceAll('{date}', metrics.date),
            subtitle: l10n
                .t('admin_dashboard_subtitle')
                .replaceAll('{timezone}', metrics.timezone)
                .replaceAll('{updatedAt}', metrics.updatedAt),
            trailing: IconButton(
              tooltip: l10n.t('admin_dashboard_refresh'),
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
            title: l10n.t('admin_dashboard_needs_attention'),
            subtitle: l10n.t('admin_dashboard_needs_attention_sub'),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppUi.kpiMetricCard(
                label: l10n.t('admin_dashboard_unassigned'),
                value: '${metrics.bookings.unassigned}',
                icon: Icons.person_add_alt,
                tone: AppStatusTone.warning,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.kpiMetricCard(
                label: l10n.t('admin_dashboard_active_trips'),
                value: '$activeTrips',
                icon: Icons.route,
                tone: AppStatusTone.info,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.kpiMetricCard(
                label: l10n.t('admin_dashboard_overdue_settlements'),
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
            title: l10n.t('admin_dashboard_operational_focus'),
            subtitle: l10n.t('admin_dashboard_operational_focus_sub'),
          ),
          _FocusTile(
            label: l10n.t('admin_dashboard_bookings_needing_assignment'),
            value: metrics.bookings.unassigned,
            tone: AppStatusTone.warning,
            onTap: widget.onOpenDispatch,
          ),
          const SizedBox(height: 8),
          _FocusTile(
            label: l10n.t('admin_dashboard_active_trips'),
            value: activeTrips,
            tone: AppStatusTone.info,
            onTap: widget.onOpenDispatch,
          ),
          const SizedBox(height: 8),
          _FocusTile(
            label: l10n.t('admin_dashboard_overdue_settlements'),
            value: metrics.settlements.overdue,
            tone: metrics.settlements.overdue > 0 ? AppStatusTone.error : AppStatusTone.neutral,
            onTap: widget.onOpenSettlements,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.sectionHeader(
            context,
            title: l10n.t('admin_dashboard_today_bookings_section'),
            subtitle: l10n.t('admin_dashboard_today_bookings_sub'),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_today_bookings'),
                value: '${metrics.bookings.today}',
                icon: Icons.today,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_assigned'),
                value: '${metrics.bookings.assigned}',
                icon: Icons.assignment_ind,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_on_route'),
                value: '${metrics.bookings.onRoute}',
                icon: Icons.route,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_arrived'),
                value: '${metrics.bookings.arrived}',
                icon: Icons.pin_drop,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_completed'),
                value: '${metrics.bookings.completed}',
                icon: Icons.check_circle,
                onTap: widget.onOpenDispatch,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_cancelled'),
                value: '${metrics.bookings.cancelled}',
                icon: Icons.cancel,
                onTap: widget.onOpenDispatch,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.sectionHeader(context, title: l10n.t('admin_dashboard_fleet_finance')),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_online_drivers'),
                value: '${metrics.drivers.online}',
                icon: Icons.local_taxi,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_pending_settlements'),
                value: '${metrics.settlements.pending}',
                icon: Icons.receipt_long,
                onTap: widget.onOpenSettlements,
              ),
              AppUi.metricCard(
                label: l10n.t('admin_dashboard_today_revenue'),
                value: _money(l10n, metrics.revenue.todayBooked, metrics.revenue.currency),
                icon: Icons.payments,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.surfaceMuted,
            child: Text(
              l10n
                  .t('admin_dashboard_completed_revenue_today')
                  .replaceAll('{amount}', _money(l10n, metrics.revenue.todayCompleted, metrics.revenue.currency)),
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _money(AppLocalizations l10n, num? amount, String currency) {
    if (amount == null) return l10n.t('admin_dashboard_mixed_currencies');
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
