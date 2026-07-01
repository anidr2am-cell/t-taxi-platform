import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class LandingReassuranceCard extends StatelessWidget {
  const LandingReassuranceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTokens.accentLight,
          borderRadius: AppTokens.borderRadiusMd,
          border: Border.all(color: AppTokens.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.waving_hand_outlined, color: AppTokens.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.t('landing_reassurance_body'),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
