import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class LandingBookingLookupCard extends StatelessWidget {
  final VoidCallback onLookup;

  const LandingBookingLookupCard({super.key, required this.onLookup});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AppUi.surfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('landing_booking_lookup_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.t('landing_booking_lookup_desc'),
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLookup,
                icon: const Icon(Icons.search_outlined),
                label: Text(l10n.t('landing_booking_lookup_action')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: AppTokens.border),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
