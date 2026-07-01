import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class LandingFooter extends StatelessWidget {
  final VoidCallback? onAdmin;
  final VoidCallback? onDriver;

  const LandingFooter({
    super.key,
    this.onAdmin,
    this.onDriver,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          Text(
            l10n.t('landing_footer_note'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTokens.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '© ${DateTime.now().year} ${l10n.t('app_title')}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppTokens.textMuted,
            ),
          ),
          if (onAdmin != null || onDriver != null) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                if (onAdmin != null)
                  TextButton(
                    onPressed: onAdmin,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 36),
                      foregroundColor: AppTokens.textMuted,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                  ),
                if (onDriver != null)
                  TextButton(
                    onPressed: onDriver,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 36),
                      foregroundColor: AppTokens.textMuted,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: const Icon(Icons.local_taxi_outlined, size: 16),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
