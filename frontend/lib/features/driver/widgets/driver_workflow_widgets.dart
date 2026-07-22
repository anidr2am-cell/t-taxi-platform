import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';

class DriverStepIndicator extends StatelessWidget {
  const DriverStepIndicator({super.key, required this.booking});

  final DriverBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = DriverUx.tripStepInfo(booking);
    if (step == null) return const SizedBox.shrink();

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n
                .t('driver_step_progress')
                .replaceAll('{step}', '${step.step}')
                .replaceAll('{total}', '${step.totalSteps}'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            l10n.t(step.titleKey),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTokens.primaryDark,
            ),
          ),
          if (step.hintKey != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.t(step.hintKey!),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: step.step / step.totalSteps,
              backgroundColor: AppTokens.surface,
              color: AppTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class DriverSettlementBlockBanner extends StatelessWidget {
  const DriverSettlementBlockBanner({
    super.key,
    required this.message,
    required this.onOpenSettlement,
  });

  final String message;
  final VoidCallback onOpenSettlement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.errorLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.block, color: AppTokens.error, size: 22),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('driver_settlement_block_title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTokens.error,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    Text(
                      message.trim().isNotEmpty
                          ? message
                          : l10n.t('driver_settlement_block_message'),
                      style: const TextStyle(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onOpenSettlement,
              icon: const Icon(Icons.payments_outlined),
              label: Text(l10n.t('driver_settlement_block_cta')),
            ),
          ),
        ],
      ),
    );
  }
}
