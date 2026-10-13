import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/driver_booking.dart';
import '../pages/driver_support_page.dart';

class DriverCustomerContactCard extends StatelessWidget {
  const DriverCustomerContactCard({
    super.key,
    required this.contact,
    this.legacyPhone,
  });

  final DriverCustomerContact? contact;
  final String? legacyPhone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: AppTokens.cardDecorationFlat(
        color: AppTokens.primaryLight,
        borderColor: AppTokens.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('driver_contact_title'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTokens.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            l10n.t('driver_contact_via_admin'),
            key: const ValueKey('driverCustomerContactViaAdmin'),
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('driverCustomerContactAdminButton'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DriverSupportPage(),
                ),
              ),
              icon: const Icon(Icons.support_agent_outlined),
              label: Text(l10n.t('driver_support_title')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTokens.primary,
                side: const BorderSide(color: AppTokens.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: AppTokens.spaceSm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
