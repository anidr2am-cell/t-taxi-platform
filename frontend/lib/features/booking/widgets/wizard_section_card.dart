import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import 'wizard_compact.dart';

class WizardSectionCard extends StatelessWidget {
  const WizardSectionCard({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.child,
    this.validationHint,
  });

  final int stepNumber;
  final String title;
  final Widget child;
  final String? validationHint;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: WizardCompact.headerPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppTokens.primary.withValues(alpha: 0.12),
                  child: Text(
                    '$stepNumber',
                    style: const TextStyle(
                      color: AppTokens.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: WizardCompact.bodyPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (validationHint != null && validationHint!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WizardCompact.fieldGap),
                    child: Text(
                      validationHint!,
                      style: WizardCompact.validationTextStyle,
                      softWrap: true,
                    ),
                  ),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
