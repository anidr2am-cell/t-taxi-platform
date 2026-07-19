import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';

class DriverSupportPage extends StatelessWidget {
  const DriverSupportPage({
    super.key,
    this.api = const PlatformSettingsApiService(),
  });
  final PlatformSettingsApiService api;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_support_title'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: api.getPublic(),
        builder: (context, snapshot) => ListView(
          padding: AppUi.pagePadding(context),
          children: [
            AppUi.adminDetailSection(
              context: context,
              title: l10n.t('driver_support_resources'),
              child: Text(l10n.t('driver_support_empty')),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.adminDetailSection(
              context: context,
              title: l10n.t('driver_support_faq'),
              child: Text(l10n.t('driver_support_empty')),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.adminDetailSection(
              context: context,
              title: l10n.t('driver_support_inquiry'),
              child: _lineContent(l10n, snapshot.data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineContent(AppLocalizations l10n, Map<String, dynamic>? settings) {
    final path = settings?['lineQrImageUrl'] as String?;
    final description = (settings?['lineQrDescription'] as String?)?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.t('driver_support_line_help')),
        const SizedBox(height: AppTokens.spaceSm),
        if (description != null && description.isNotEmpty) ...[
          Text(
            description,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
        ],
        if (path == null || path.isEmpty)
          Text(l10n.t('support_line_qr_missing'))
        else
          Image.network(
            api.assetUri(path).toString(),
            height: 240,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                Text(l10n.t('support_line_qr_missing')),
          ),
      ],
    );
  }
}
