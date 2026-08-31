import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import 'landing_auth_bottom_sheet.dart';

/// Lightweight signed-out CTA that opens the shared auth modal.
class LandingLoginPromptBanner extends StatelessWidget {
  const LandingLoginPromptBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Semantics(
      button: true,
      label: l10n.t('landing_login_prompt_cta'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('landing_login_prompt_banner'),
          onTap: () => showLandingAuthBottomSheet(context),
          borderRadius: AppTokens.cardRadius,
          child: Ink(
            decoration: AppTokens.cardDecorationFlat(
              color: AppTokens.primaryLight,
              borderColor: AppTokens.primary.withValues(alpha: 0.15),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.cardPadding,
                vertical: AppTokens.cardPadding,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 22,
                    color: AppTokens.primary,
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: Text(
                      l10n.t('landing_login_prompt_cta'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: AppTokens.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
