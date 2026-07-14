import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_status.dart';
import '../services/driver_api_service.dart';

class DriverStatusControl extends StatefulWidget {
  const DriverStatusControl({
    super.key,
    required this.api,
    this.onStatusChanged,
    this.padding = const EdgeInsets.fromLTRB(
      AppTokens.spaceMd,
      AppTokens.spaceSm,
      AppTokens.spaceMd,
      AppTokens.spaceSm,
    ),
  });

  final DriverApiService api;
  final VoidCallback? onStatusChanged;
  final EdgeInsetsGeometry padding;

  @override
  State<DriverStatusControl> createState() => _DriverStatusControlState();
}

class _DriverStatusControlState extends State<DriverStatusControl> {
  late Future<DriverStatus> _future;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getStatus();
  }

  void refresh() {
    setState(() {
      _future = widget.api.getStatus();
      _error = null;
    });
  }

  Future<void> _setOnlineState(bool online, DriverStatus? current) async {
    if (_updating) return;

    if (!online) {
      if (current?.hasActiveJob == true) {
        setState(() {
          _error = context.l10n.t('driver_profile_offline_blocked');
        });
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.t('driver_profile_offline_confirm')),
          content: Text(context.l10n.t('driver_session_offline')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.t('driver_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.t('driver_profile_go_offline')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final next = online
          ? await widget.api.goOnline()
          : await widget.api.goOffline();
      if (!mounted) return;
      setState(() {
        _future = Future.value(next);
        _updating = false;
      });
      widget.onStatusChanged?.call();
    } catch (err) {
      if (!mounted) return;
      if (driverIsAuthError(err)) {
        setState(() => _updating = false);
        driverHandleApiError(context, err);
        return;
      }
      setState(() {
        _updating = false;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_action_failed'),
        );
        _future = widget.api.getStatus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.background,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: widget.padding,
          child: FutureBuilder<DriverStatus>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _StatusFrame(
                  backgroundColor: AppTokens.surface,
                  borderColor: AppTokens.border,
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          context.l10n.t('driver_profile_status_loading'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                final err = snapshot.error!;
                if (driverIsAuthError(err)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) driverHandleApiError(context, err);
                  });
                }
                return _StatusFrame(
                  backgroundColor: AppTokens.errorLight,
                  borderColor: AppTokens.error,
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTokens.error),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          context.l10n.t('driver_profile_status_error'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: refresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: context.l10n.t('driver_retry'),
                      ),
                    ],
                  ),
                );
              }
              return _StatusContent(
                status: snapshot.data!,
                updating: _updating,
                error: _error,
                onGoOnline: () => _setOnlineState(true, snapshot.data),
                onGoOffline: () => _setOnlineState(false, snapshot.data),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.status,
    required this.updating,
    required this.error,
    required this.onGoOnline,
    required this.onGoOffline,
  });

  final DriverStatus status;
  final bool updating;
  final String? error;
  final VoidCallback onGoOnline;
  final VoidCallback onGoOffline;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activeJob = status.hasActiveJob;
    final online = status.online;
    final eligibility = status.callEligibility;
    final reasonCode = activeJob
        ? DriverCallEligibilityReason.activeTrip
        : eligibility.reasonCode;
    final state = activeJob
        ? _StatusVisual(
            icon: Icons.local_taxi,
            label: l10n.t('driver_call_status_active_trip'),
            helper: l10n.t(_callStatusMessageKey(reasonCode)),
            backgroundColor: AppTokens.warningLight,
            borderColor: AppTokens.warning,
            iconColor: AppTokens.warning,
          )
        : online
        ? _StatusVisual(
            icon: eligibility.canReceiveCalls
                ? Icons.check_circle
                : Icons.info_outline,
            label: l10n.t('driver_online'),
            helper: l10n.t(_callStatusMessageKey(reasonCode)),
            backgroundColor: eligibility.canReceiveCalls
                ? AppTokens.successLight
                : AppTokens.warningLight,
            borderColor: eligibility.canReceiveCalls
                ? AppTokens.success
                : AppTokens.warning,
            iconColor: eligibility.canReceiveCalls
                ? AppTokens.success
                : AppTokens.warning,
          )
        : _StatusVisual(
            icon: Icons.pause_circle_filled,
            label: l10n.t('driver_offline'),
            helper: l10n.t(_callStatusMessageKey(reasonCode)),
            backgroundColor: AppTokens.surfaceMuted,
            borderColor: AppTokens.textMuted,
            iconColor: AppTokens.textMuted,
          );

    final button = SizedBox(
      width: double.infinity,
      height: 50,
      child: online
          ? OutlinedButton.icon(
              onPressed: updating || activeJob ? null : onGoOffline,
              icon: updating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.power_settings_new),
              label: Text(
                l10n.t('driver_profile_go_offline'),
                textAlign: TextAlign.center,
              ),
            )
          : FilledButton.icon(
              onPressed: updating ? null : onGoOnline,
              icon: updating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_fill),
              label: Text(
                l10n.t('driver_profile_go_online'),
                textAlign: TextAlign.center,
              ),
            ),
    );

    return _StatusFrame(
      backgroundColor: state.backgroundColor,
      borderColor: state.borderColor,
      onTap: () => _showStatusDetail(context, reasonCode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final summary = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(state.icon, color: state.iconColor, size: 28),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.helper,
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    const SizedBox(height: AppTokens.spaceSm),
                    button,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: AppTokens.spaceMd),
                  SizedBox(width: 220, child: button),
                ],
              );
            },
          ),
          if (updating) ...[
            const SizedBox(height: AppTokens.spaceSm),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (error != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(error!, style: const TextStyle(color: AppTokens.error)),
          ],
        ],
      ),
    );
  }
}

String _callStatusMessageKey(String reasonCode) {
  switch (reasonCode) {
    case DriverCallEligibilityReason.ready:
      return 'driver_call_status_ready';
    case DriverCallEligibilityReason.offline:
      return 'driver_call_status_offline';
    case DriverCallEligibilityReason.activeTrip:
      return 'driver_call_status_active_trip_helper';
    case DriverCallEligibilityReason.unpaidSettlement:
      return 'driver_call_status_settlement_required';
    case DriverCallEligibilityReason.customerComplaintReview:
      return 'driver_call_status_customer_issue_review';
    case DriverCallEligibilityReason.accountUnderReview:
      return 'driver_call_status_account_under_review';
    case DriverCallEligibilityReason.accountRestricted:
      return 'driver_call_status_account_restricted';
    case DriverCallEligibilityReason.driverApprovalPending:
      return 'driver_call_status_driver_approval_pending';
    case DriverCallEligibilityReason.vehicleReviewRequired:
      return 'driver_call_status_vehicle_review_required';
    default:
      return 'driver_call_status_unknown';
  }
}

String _callStatusDetailKey(String reasonCode) {
  switch (reasonCode) {
    case DriverCallEligibilityReason.ready:
      return 'driver_call_status_detail_ready';
    case DriverCallEligibilityReason.offline:
      return 'driver_call_status_detail_offline';
    case DriverCallEligibilityReason.activeTrip:
      return 'driver_call_status_detail_active_trip';
    case DriverCallEligibilityReason.unpaidSettlement:
      return 'driver_call_status_detail_settlement_required';
    case DriverCallEligibilityReason.customerComplaintReview:
      return 'driver_call_status_detail_customer_issue_review';
    case DriverCallEligibilityReason.accountUnderReview:
      return 'driver_call_status_detail_account_under_review';
    case DriverCallEligibilityReason.accountRestricted:
      return 'driver_call_status_detail_account_restricted';
    case DriverCallEligibilityReason.driverApprovalPending:
      return 'driver_call_status_detail_driver_approval_pending';
    case DriverCallEligibilityReason.vehicleReviewRequired:
      return 'driver_call_status_detail_vehicle_review_required';
    default:
      return 'driver_call_status_detail_unknown';
  }
}

void _showStatusDetail(BuildContext context, String reasonCode) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceLg,
          AppTokens.spaceSm,
          AppTokens.spaceLg,
          AppTokens.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('driver_call_status_detail_title'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              context.l10n.t(_callStatusMessageKey(reasonCode)),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(context.l10n.t(_callStatusDetailKey(reasonCode))),
            const SizedBox(height: AppTokens.spaceMd),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.t('support_close_button')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusFrame extends StatelessWidget {
  const _StatusFrame({
    required this.child,
    required this.backgroundColor,
    required this.borderColor,
    this.onTap,
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = AppTokens.borderRadiusLg;
    return Material(
      color: backgroundColor,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: borderColor.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: child,
        ),
      ),
    );
  }
}

class _StatusVisual {
  const _StatusVisual({
    required this.icon,
    required this.label,
    required this.helper,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String helper;
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
}
