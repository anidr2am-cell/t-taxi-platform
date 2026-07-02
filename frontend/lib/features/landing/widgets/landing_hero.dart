import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import 'landing_clickable_styles.dart';

class LandingHero extends StatelessWidget {
  final VoidCallback onBook;

  static const pattayaHeroAssetPath = 'assets/images/pattaya_hero.jpg';
  static const hasPattayaHeroAsset = false;

  const LandingHero({super.key, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Container(
      key: const Key('landing_hero'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 36 : 20,
        vertical: isWide ? 40 : 24,
      ),
      decoration: BoxDecoration(
        image: hasPattayaHeroAsset
            ? const DecorationImage(
                image: AssetImage(pattayaHeroAssetPath),
                fit: BoxFit.cover,
              )
            : null,
        gradient: hasPattayaHeroAsset ? null : AppTokens.heroGradient,
        borderRadius: AppTokens.borderRadiusLg,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(
                  0xFF062D33,
                ).withValues(alpha: hasPattayaHeroAsset ? 0.54 : 0.18),
                borderRadius: AppTokens.borderRadiusLg,
              ),
            ),
          ),
          if (hasPattayaHeroAsset)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppTokens.borderRadiusLg,
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF052E34).withValues(alpha: 0.62),
                      const Color(0xFF052E34).withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _heroCopy(l10n, compact: false)),
                    const SizedBox(width: 32),
                    _ctaColumn(l10n, onBook, fullWidth: false, compact: false),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heroCopy(l10n, compact: true),
                    const SizedBox(height: 20),
                    _ctaColumn(l10n, onBook, fullWidth: true, compact: true),
                  ],
                ),
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
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.t('landing_hero_body'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: compact ? 14 : 15,
            height: 1.45,
            shadows: const [
              Shadow(
                color: Color(0x55000000),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 16,
                color: Colors.white.withValues(alpha: 0.75),
              ),
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

  Widget _ctaColumn(
    AppLocalizations l10n,
    VoidCallback onBook, {
    required bool fullWidth,
    required bool compact,
  }) {
    final button = Semantics(
      button: true,
      label: l10n.t('landing_hero_cta'),
      child: FilledButton(
        onPressed: onBook,
        style: LandingClickableStyles.heroCtaStyle(compact: compact),
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
        children: [button, const SizedBox(height: 8), helper],
      ),
    );
  }
}
