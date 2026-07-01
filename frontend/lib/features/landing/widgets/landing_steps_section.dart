import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class LandingStepsSection extends StatelessWidget {
  const LandingStepsSection({super.key});

  static const _steps = [
    _StepItem(
      number: 1,
      titleKey: 'landing_how_step_1_title',
      descKey: 'landing_how_step_1_desc',
    ),
    _StepItem(
      number: 2,
      titleKey: 'landing_how_step_2_title',
      descKey: 'landing_how_step_2_desc',
    ),
    _StepItem(
      number: 3,
      titleKey: 'landing_how_step_3_title',
      descKey: 'landing_how_step_3_desc',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width >= 768;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.sectionHeader(context, title: l10n.t('landing_how_it_works_title')),
          if (horizontal)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _StepCard(l10n: l10n, step: _steps[i])),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _StepCard(l10n: l10n, step: _steps[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final AppLocalizations l10n;
  final _StepItem step;

  const _StepCard({required this.l10n, required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTokens.primary,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${step.number}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t(step.titleKey),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.t(step.descKey),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepItem {
  final int number;
  final String titleKey;
  final String descKey;

  const _StepItem({
    required this.number,
    required this.titleKey,
    required this.descKey,
  });
}
