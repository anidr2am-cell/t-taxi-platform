import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/booking_wizard_steps.dart';

class BookingProgressHeader extends StatelessWidget {
  const BookingProgressHeader({
    super.key,
    required this.currentStep,
  });

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stepNumber = currentStep + 1;
    final title = l10n.t(BookingWizardSteps.titleKey(currentStep));
    final label = l10n
        .t('wizard_step_indicator')
        .replaceAll('{current}', '$stepNumber')
        .replaceAll('{total}', '${BookingWizardSteps.stepCount}')
        .replaceAll('{title}', title);

    final width = MediaQuery.sizeOf(context).width;
    final showDesktopSteps = width >= 720;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (showDesktopSteps) ...[
            const SizedBox(height: 10),
            _DesktopStepRow(currentStep: currentStep, l10n: l10n),
          ],
        ],
      ),
    );
  }
}

class _DesktopStepRow extends StatelessWidget {
  const _DesktopStepRow({
    required this.currentStep,
    required this.l10n,
  });

  final int currentStep;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < BookingWizardSteps.stepCount; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= currentStep
                    ? AppTokens.primary
                    : AppTokens.border,
              ),
            ),
          _StepDot(
            index: i + 1,
            label: l10n.t(BookingWizardSteps.titleKey(i)),
            isActive: i == currentStep,
            isComplete: i < currentStep,
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  final int index;
  final String label;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final color = isActive || isComplete
        ? AppTokens.primary
        : AppTokens.textSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: isActive
              ? AppTokens.primary
              : (isComplete ? AppTokens.primaryLight : AppTokens.border),
          child: Text(
            '$index',
            style: TextStyle(
              color: isActive ? Colors.white : color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isActive ? AppTokens.textPrimary : AppTokens.textSecondary,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
