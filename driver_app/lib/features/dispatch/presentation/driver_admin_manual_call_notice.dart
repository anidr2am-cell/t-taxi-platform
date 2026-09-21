import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class DriverAdminManualCallNotice extends StatelessWidget {
  const DriverAdminManualCallNotice({
    super.key,
    required this.isAdminManualCall,
    required this.requiresBankAccountConfirmation,
  });

  final bool isAdminManualCall;
  final bool requiresBankAccountConfirmation;

  @override
  Widget build(BuildContext context) {
    if (!isAdminManualCall) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('driverAdminManualCallNotice'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(l10n.driverCallBadgeAdminManual),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
            Chip(
              label: Text(l10n.driverCallBadgeNoCommission),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            ),
          ],
        ),
        if (requiresBankAccountConfirmation) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withValues(
              alpha: 0.35,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.driverCallBankAccountConfirmNotice,
                      style: const TextStyle(
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
