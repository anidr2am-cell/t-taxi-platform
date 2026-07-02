import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'landing_clickable_styles.dart';

class LandingBottomCta extends StatelessWidget {
  final VoidCallback onBook;

  const LandingBottomCta({super.key, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        button: true,
        label: l10n.t('landing_hero_cta'),
        child: FilledButton(
          onPressed: onBook,
          style: LandingClickableStyles.heroCtaStyle(compact: true),
          child: Text(l10n.t('landing_hero_cta')),
        ),
      ),
    );
  }
}
