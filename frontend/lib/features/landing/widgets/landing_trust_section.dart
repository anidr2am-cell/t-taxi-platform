import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class LandingTrustSection extends StatelessWidget {
  const LandingTrustSection({super.key});

  static const _items = [
    _TrustItem(key: 'trust_flight_delay', icon: Icons.schedule),
    _TrustItem(key: 'trust_fixed_pricing', icon: Icons.payments_outlined),
    _TrustItem(key: 'trust_professional_drivers', icon: Icons.verified_user_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : (width >= 600 ? 2 : 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.sectionHeader(context, title: l10n.t('landing_trust_title')),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 3.5 : 2.2,
            children: _items.map((item) {
              return AppUi.surfaceCard(
                backgroundColor: AppTokens.primaryLight,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(item.icon, color: AppTokens.primary, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.t(item.key),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TrustItem {
  final String key;
  final IconData icon;

  const _TrustItem({required this.key, required this.icon});
}
