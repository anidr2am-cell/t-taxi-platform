import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

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
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 48 : 24,
        vertical: isWide ? 56 : 32,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
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
        const Icon(Icons.local_taxi, size: 48, color: Colors.white),
        const SizedBox(height: 16),
        Text(
          l10n.t('landing_hero_title'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 16),
        ...highlights.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _ctaButton(AppLocalizations l10n, VoidCallback onBook, {required bool fullWidth}) {
    final button = ElevatedButton(
      onPressed: onBook,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(l10n.t('book_your_ride')),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
