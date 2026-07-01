import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class LandingHero extends StatelessWidget {
  final VoidCallback onBook;

  const LandingHero({super.key, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 36 : 20,
        vertical: isWide ? 40 : 24,
      ),
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient,
        borderRadius: AppTokens.borderRadiusLg,
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _heroCopy(l10n, compact: false)),
                const SizedBox(width: 32),
                _ctaColumn(l10n, onBook, fullWidth: false),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heroCopy(l10n, compact: true),
                const SizedBox(height: 20),
                _ctaColumn(l10n, onBook, fullWidth: true),
              ],
            ),
    );
  }

  Widget _heroCopy(AppLocalizations l10n, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('landing_hero_eyebrow'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.t('landing_hero_title'),
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 24 : 30,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.t('landing_hero_body'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: compact ? 14 : 15,
            height: 1.45,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 16, color: Colors.white.withValues(alpha: 0.75)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.t('landing_hero_helper'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _ctaColumn(AppLocalizations l10n, VoidCallback onBook, {required bool fullWidth}) {
    final button = Semantics(
      button: true,
      label: l10n.t('landing_hero_cta'),
      child: FilledButton(
        onPressed: onBook,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        child: Text(l10n.t('landing_hero_cta')),
      ),
    );

    final helper = Text(
      l10n.t('landing_hero_helper'),
      textAlign: fullWidth ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.78),
        fontSize: 12,
        height: 1.3,
      ),
    );

    if (fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: double.infinity, child: button),
          const SizedBox(height: 8),
          helper,
        ],
      );
    }

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          const SizedBox(height: 8),
          helper,
        ],
      ),
    );
  }
}
