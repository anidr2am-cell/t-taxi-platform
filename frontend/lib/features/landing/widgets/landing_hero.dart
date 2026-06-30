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

    final highlights = [
      l10n.t('landing_highlight_fixed_price'),
      l10n.t('landing_highlight_flight'),
      l10n.t('landing_highlight_support'),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 24,
        vertical: isWide ? 48 : 32,
      ),
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient,
        borderRadius: AppTokens.borderRadiusLg,
        boxShadow: AppTokens.cardShadow(color: AppTokens.primary),
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _heroText(l10n, highlights)),
                const SizedBox(width: 32),
                _ctaButton(l10n, onBook, fullWidth: false),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heroText(l10n, highlights),
                const SizedBox(height: 24),
                _ctaButton(l10n, onBook, fullWidth: true),
              ],
            ),
    );
  }

  Widget _heroText(AppLocalizations l10n, List<String> highlights) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: AppTokens.borderRadiusMd,
          ),
          child: const Icon(Icons.flight_land, size: 32, color: Colors.white),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.t('landing_hero_title'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.t('landing_services_title'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        ...highlights.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppTokens.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _ctaButton(AppLocalizations l10n, VoidCallback onBook, {required bool fullWidth}) {
    final button = FilledButton.icon(
      onPressed: onBook,
      icon: const Icon(Icons.arrow_forward),
      label: Text(l10n.t('book_your_ride')),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
