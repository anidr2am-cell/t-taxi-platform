import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class LandingSupportOneClickCta extends StatelessWidget {
  const LandingSupportOneClickCta({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Semantics(
        button: true,
        label: l10n.t('landing_support_one_click_cta'),
        child: FilledButton(
          key: const Key('landing_support_one_click_cta'),
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppTokens.info,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppTokens.borderRadiusMd,
            ),
          ),
          child: Text(l10n.t('landing_support_one_click_cta')),
        ),
      ),
    );
  }
}
