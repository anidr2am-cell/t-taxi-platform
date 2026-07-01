import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class WizardStepIndicator extends StatelessWidget {
  final int completedRequired;
  final int totalRequired;

  const WizardStepIndicator({
    super.key,
    required this.completedRequired,
    required this.totalRequired,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ratio = totalRequired == 0 ? 0.0 : completedRequired / totalRequired;
    final percent = (ratio * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n
                      .t('wizard_completion_progress')
                      .replaceAll('{completed}', '$completedRequired')
                      .replaceAll('{total}', '$totalRequired'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTokens.textSecondary,
                        fontSize: 13,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTokens.primary,
                      fontSize: 13,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppTokens.border,
              color: AppTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}
