import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/contact_channel.dart';
import '../services/booking_contact_connection_service.dart';
import 'fare_inquiry_card.dart';

class PreferredSupportButton extends StatefulWidget {
  const PreferredSupportButton({super.key});
  @override
  State<PreferredSupportButton> createState() => _PreferredSupportButtonState();
}

class _PreferredSupportButtonState extends State<PreferredSupportButton> {
  late final _channels = BookingContactConnectionService().getPublicChannels();
  @override
  Widget build(BuildContext context) => FutureBuilder<List<ContactChannel>>(
    future: _channels,
    builder: (context, snapshot) {
      final channels = orderContactChannels(
        snapshot.data ?? [],
        context.l10n.languageCode,
      );
      final channel = channels.isEmpty ? null : channels.first;
      return Padding(
        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(
            channel == null
                ? context.l10n.t('landing_support_cta')
                : '${context.l10n.t('landing_support_cta')} · ${channel.displayName}',
          ),
          onPressed: () async {
            final uri = channel == null ? null : fareInquiryChannelUri(channel);
            if (uri != null &&
                await launchUrl(uri, mode: LaunchMode.externalApplication))
              return;
            if (context.mounted) Navigator.pushNamed(context, '/support');
          },
        ),
      );
    },
  );
}
