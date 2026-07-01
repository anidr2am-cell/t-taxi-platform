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
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final useRow = width >= 768;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.sectionHeader(context, title: l10n.t('landing_trust_title')),
          if (useRow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _TrustCard(l10n: l10n, item: _items[i])),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _TrustCard(l10n: l10n, item: _items[i]),
                ],
              ],
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
      padding: const EdgeInsets.all(14),
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
