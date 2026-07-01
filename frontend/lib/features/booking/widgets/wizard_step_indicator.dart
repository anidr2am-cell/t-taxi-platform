import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class WizardStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const WizardStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n
                    .t('wizard_step_progress')
                    .replaceAll('{current}', '${currentStep + 1}')
                    .replaceAll('{total}', '$totalSteps'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTokens.textSecondary,
                    ),
              ),
              Text(
                '${((currentStep + 1) / totalSteps * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTokens.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (currentStep + 1) / totalSteps,
              minHeight: 6,
              backgroundColor: AppTokens.border,
              color: AppTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}
