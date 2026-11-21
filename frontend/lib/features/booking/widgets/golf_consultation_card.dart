import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../services/booking_contact_connection_service.dart';
import '../utils/contact_channel_url.dart';

/// Transport and tee-time confirmation are separate services.
class GolfConsultationCard extends StatelessWidget {
  const GolfConsultationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!const ['ja', 'zh-TW'].contains(l10n.languageCode)) {
      return const SizedBox.shrink();
    }
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('ux_golf_title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.t('ux_golf_help')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_outlined),
            label: Text(l10n.t('ux_official_line')),
            onPressed: () async {
              try {
                final channels = await BookingContactConnectionService()
                    .getPublicChannels();
                final line = channels.where((c) => c.code == 'LINE');
                final uri = line.isEmpty
                    ? null
                    : parseAllowedContactChannelUrl(line.first.addUrl ?? '');
                if (uri != null &&
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    )) {
                  return;
                }
              } catch (_) {
                // The central support screen also offers the other channels.
              }
              if (context.mounted) Navigator.pushNamed(context, '/support');
            },
          ),
        ],
      ),
    );
  }
}
