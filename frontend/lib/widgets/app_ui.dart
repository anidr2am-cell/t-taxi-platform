import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shared UI building blocks for customer, admin, and driver surfaces.
abstract final class AppUi {
  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width >= 900 ? AppTokens.spaceXl : AppTokens.spaceMd;
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: AppTokens.spaceMd);
  }

  static Widget sectionHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  static Widget surfaceCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(AppTokens.spaceMd),
    Color? backgroundColor,
    VoidCallback? onTap,
  }) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTokens.surface,
        borderRadius: AppTokens.borderRadiusLg,
        border: Border.all(color: AppTokens.border),
        boxShadow: AppTokens.cardShadow(),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusLg,
        child: card,
      ),
    );
  }

  static Widget summaryRow({
    required String label,
    required String value,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: AppTokens.textSecondary, fontSize: 14),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 16 : 14,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                color: emphasize ? AppTokens.primaryDark : AppTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget statusBadge(
    String label, {
    AppStatusTone tone = AppStatusTone.neutral,
  }) {
    final colors = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.15)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static Widget loadingState({String? message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (message != null) ...[
              const SizedBox(height: AppTokens.spaceMd),
              Text(message, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  static Widget emptyState({
    required String title,
    String? message,
    IconData icon = Icons.inbox_outlined,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTokens.textMuted),
            const SizedBox(height: AppTokens.spaceSm),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (message != null) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTokens.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget errorState({
    required String message,
    VoidCallback? onRetry,
    String retryLabel = 'Retry',
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTokens.error),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTokens.spaceMd),
              ElevatedButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }

  static Widget selectionTile({
    required String title,
    String? subtitle,
    IconData? icon,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return surfaceCard(
      onTap: onTap,
      backgroundColor: selected ? AppTokens.primaryLight : AppTokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? AppTokens.primary.withValues(alpha: 0.12)
                    : AppTokens.surfaceMuted,
                borderRadius: AppTokens.borderRadiusSm,
              ),
              child: Icon(
                icon,
                color: selected ? AppTokens.primary : AppTokens.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? AppTokens.primaryDark : AppTokens.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13)),
                ],
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? AppTokens.primary : AppTokens.textMuted,
          ),
        ],
      ),
    );
  }

  static Widget wizardFooter({
    required Widget leading,
    required Widget primaryAction,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        border: Border(top: BorderSide(color: AppTokens.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Row(
            children: [
              leading,
              const Spacer(),
              primaryAction,
            ],
          ),
        ),
      ),
    );
  }

  static Widget primaryButton({
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
    bool loading = false,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon ?? Icons.arrow_forward),
        label: Text(label),
      ),
    );
  }

  static Widget secondaryButton({
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
    bool fullWidth = false,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.search),
      label: Text(label),
    );
    if (!fullWidth) return button;
    return SizedBox(width: double.infinity, height: 48, child: button);
  }

  static Widget selectedInfoCard({
    required String title,
    String? subtitle,
    String? meta,
    IconData icon = Icons.place_outlined,
    String? changeLabel,
    VoidCallback? onChange,
    bool loading = false,
  }) {
    return surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTokens.primary.withValues(alpha: 0.12),
              borderRadius: AppTokens.borderRadiusSm,
            ),
            child: Icon(icon, color: AppTokens.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppTokens.textSecondary)),
                ],
                if (meta != null && meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, style: const TextStyle(color: AppTokens.textMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (changeLabel != null && onChange != null)
            TextButton(onPressed: loading ? null : onChange, child: Text(changeLabel)),
        ],
      ),
    );
  }

  static Widget counterRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int min = 0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: Icon(
              Icons.remove_circle_outline,
              color: value > min ? AppTokens.primary : AppTokens.textMuted,
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline, color: AppTokens.primary),
          ),
        ],
      ),
    );
  }

  static Widget centeredContent({required Widget child, double maxWidth = AppTokens.maxContentWidth}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  static Widget metricCard({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    final interactive = onTap != null;
    return SizedBox(
      width: 180,
      child: surfaceCard(
        onTap: onTap,
        backgroundColor: interactive ? AppTokens.surface : AppTokens.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppTokens.primary).withValues(alpha: 0.12),
                    borderRadius: AppTokens.borderRadiusSm,
                  ),
                  child: Icon(icon, color: iconColor ?? AppTokens.primary, size: 22),
                ),
                if (interactive) ...[
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppTokens.textMuted, size: 18),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  static Widget kpiMetricCard({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    AppStatusTone tone = AppStatusTone.warning,
  }) {
    final colors = _toneColors(tone);
    return SizedBox(
      width: 200,
      child: surfaceCard(
        onTap: onTap,
        backgroundColor: colors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.foreground.withValues(alpha: 0.12),
                    borderRadius: AppTokens.borderRadiusSm,
                  ),
                  child: Icon(icon, color: colors.foreground, size: 22),
                ),
                if (onTap != null) ...[
                  const Spacer(),
                  Icon(Icons.chevron_right, color: colors.foreground.withValues(alpha: 0.7), size: 18),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: colors.foreground.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget adminDetailSection({
    required BuildContext context,
    required String title,
    String? subtitle,
    required Widget child,
    Color? backgroundColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionHeader(context, title: title, subtitle: subtitle),
        surfaceCard(backgroundColor: backgroundColor, child: child),
      ],
    );
  }

  static Widget adminStickyActions({required List<Widget> actions}) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        border: Border(top: BorderSide(color: AppTokens.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actions,
          ),
        ),
      ),
    );
  }

  static Widget actionBanner({
    required String message,
    IconData icon = Icons.touch_app,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTokens.primaryLight,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTokens.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTokens.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppTokens.primary),
        ],
      ),
    );
  }

  static _ToneColors _toneColors(AppStatusTone tone) {
    switch (tone) {
      case AppStatusTone.success:
        return const _ToneColors(AppTokens.successLight, AppTokens.success);
      case AppStatusTone.warning:
        return const _ToneColors(AppTokens.warningLight, AppTokens.warning);
      case AppStatusTone.error:
        return const _ToneColors(AppTokens.errorLight, AppTokens.error);
      case AppStatusTone.info:
        return const _ToneColors(AppTokens.infoLight, AppTokens.info);
      case AppStatusTone.neutral:
        return const _ToneColors(AppTokens.surfaceMuted, AppTokens.textSecondary);
    }
  }

  static AppStatusTone toneForBookingStatus(String status) {
    switch (status) {
      case 'COMPLETED':
        return AppStatusTone.success;
      case 'CANCELLED':
      case 'NO_SHOW':
        return AppStatusTone.error;
      case 'DRIVER_ASSIGNED':
      case 'ON_ROUTE':
      case 'DRIVER_ARRIVED':
      case 'PICKED_UP':
        return AppStatusTone.info;
      case 'PENDING':
      case 'CONFIRMED':
        return AppStatusTone.warning;
      default:
        return AppStatusTone.neutral;
    }
  }

  static AppStatusTone toneForCommissionStatus(String status) {
    switch (status) {
      case 'PAID':
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
      case 'OVERDUE':
        return AppStatusTone.error;
      case 'PENDING':
      case 'RECEIPT_SUBMITTED':
        return AppStatusTone.warning;
      default:
        return AppStatusTone.neutral;
    }
  }

  static AppStatusTone toneForModerationStatus(String status) {
    switch (status) {
      case 'VISIBLE':
        return AppStatusTone.success;
      case 'HIDDEN':
        return AppStatusTone.error;
      default:
        return AppStatusTone.neutral;
    }
  }

  static AppStatusTone toneForFlightRowStatus(String status) {
    switch (status) {
      case 'DELAYED':
        return AppStatusTone.warning;
      case 'CANCELLED':
        return AppStatusTone.error;
      case 'LANDED':
      case 'ARRIVED':
        return AppStatusTone.success;
      default:
        return AppStatusTone.info;
    }
  }

  static Widget adminQueueCard({
    required Widget child,
    VoidCallback? onTap,
    Color? backgroundColor,
  }) {
    return surfaceCard(
      onTap: onTap,
      backgroundColor: backgroundColor,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: child,
    );
  }

  static Widget adminFilterBar({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Wrap(
        spacing: AppTokens.spaceSm,
        runSpacing: AppTokens.spaceSm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

enum AppStatusTone { neutral, success, warning, error, info }

class _ToneColors {
  const _ToneColors(this.background, this.foreground);
  final Color background;
  final Color foreground;
}
