import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class LandingTrustSection extends StatelessWidget {
  const LandingTrustSection({super.key});

  static const _items = [
    _TrustItem(
      titleKey: 'landing_trust_drivers_title',
      descKey: 'landing_trust_drivers_desc',
      icon: Icons.verified_user_outlined,
    ),
    _TrustItem(
      titleKey: 'landing_trust_confirmed_title',
      descKey: 'landing_trust_confirmed_desc',
      icon: Icons.event_available_outlined,
    ),
    _TrustItem(
      titleKey: 'landing_trust_comfort_title',
      descKey: 'landing_trust_comfort_desc',
      icon: Icons.airline_seat_recline_extra_outlined,
    ),
    _TrustItem(
      titleKey: 'landing_trust_refund_title',
      descKey: 'landing_trust_refund_desc',
      icon: Icons.replay_outlined,
    ),
    _TrustItem(
      titleKey: 'landing_trust_driver_policy_title',
      descKey: 'landing_trust_driver_policy_desc',
      icon: Icons.shield_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.sectionHeader(context, title: l10n.t('landing_trust_title')),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 900 ? 3 : (width >= 768 ? 2 : 1);
              const gap = 12.0;
              const runGap = 8.0;
              final itemWidth = columns == 1
                  ? width
                  : (width - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: runGap,
                children: [
                  for (final item in _items)
                    SizedBox(
                      width: itemWidth,
                      child: _TrustCard(l10n: l10n, item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrustCard extends StatelessWidget {
  final AppLocalizations l10n;
  final _TrustItem item;

  const _TrustCard({required this.l10n, required this.item});

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      padding: const EdgeInsets.all(AppTokens.cardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTokens.primaryLight,
              borderRadius: AppTokens.borderRadiusSm,
            ),
            child: Icon(item.icon, color: AppTokens.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t(item.titleKey),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.t(item.descKey),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustItem {
  final String titleKey;
  final String descKey;
  final IconData icon;

  const _TrustItem({
    required this.titleKey,
    required this.descKey,
    required this.icon,
  });
}
