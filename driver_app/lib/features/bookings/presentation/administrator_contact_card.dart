import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class AdministratorContactCard extends StatelessWidget {
  const AdministratorContactCard({super.key, this.onContact});
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.customerContactViaAdministrator),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('bookingContactAdministrator'),
              onPressed: onContact,
              icon: const Icon(Icons.support_agent_outlined),
              label: Text(
                l10n.contactAdministrator,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
