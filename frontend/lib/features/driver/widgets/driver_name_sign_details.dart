import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

/// Only the requested sign text; never substitute a customer name or contact.
class DriverNameSignDetails extends StatelessWidget {
  const DriverNameSignDetails({super.key, this.name});
  final String? name;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasName = name != null && name!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTokens.spaceSm),
        Text(l10n.t('driver_name_sign_text_label')),
        const SizedBox(height: AppTokens.spaceXs),
        SelectableText(
          hasName ? name! : l10n.t('driver_name_sign_text_missing'),
        ),
      ],
    );
  }
}
