import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'landing_clickable_styles.dart';

class LandingBottomCta extends StatelessWidget {
  final VoidCallback onSupport;

  const LandingBottomCta({super.key, required this.onSupport});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        button: true,
        label: l10n.t('landing_support_cta'),
        child: FilledButton(
          key: const Key('landing_support_cta'),
          onPressed: onSupport,
          style: LandingClickableStyles.heroCtaStyle(compact: true),
          child: Text(l10n.t('landing_support_cta')),
        ),
      ),
    );
  }
}
