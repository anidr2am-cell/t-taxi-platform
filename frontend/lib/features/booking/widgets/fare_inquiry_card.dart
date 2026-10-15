import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/contact_channel.dart';
import '../services/booking_contact_connection_service.dart';
import '../utils/contact_channel_url.dart';

Uri? fareInquiryChannelUri(ContactChannel channel) {
  final phone = channel.phoneNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
  final raw = channel.code == 'WHATSAPP' && phone.isNotEmpty
      ? 'https://wa.me/$phone' : (channel.addUrl ?? '');
  return parseAllowedContactChannelUrl(raw, allowHttp: allowHttpContactUrlsForEnvironment());
}

class FareInquiryCard extends StatefulWidget {
  const FareInquiryCard({super.key, this.loadChannels});
  final Future<List<ContactChannel>> Function()? loadChannels;
  @override
  State<FareInquiryCard> createState() => _FareInquiryCardState();
}

class _FareInquiryCardState extends State<FareInquiryCard> {
  late final _channels =
      (widget.loadChannels ??
      BookingContactConnectionService().getPublicChannels)();
  @override
  Widget build(BuildContext context) {
    final t = context.l10n.t;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('fare_inquiry_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(t('fare_inquiry_body')),
            const SizedBox(height: AppTokens.spaceMd),
            FutureBuilder<List<ContactChannel>>(
              future: _channels,
              builder: (context, snapshot) {
                final channels = orderContactChannels(snapshot.data ?? const <ContactChannel>[], context.l10n.languageCode);
                return Wrap(
                  spacing: AppTokens.spaceSm,
                  runSpacing: AppTokens.spaceSm,
                  children: [
                    for (final c in channels)
                        OutlinedButton(
                          onPressed: () async {
                            final uri = fareInquiryChannelUri(c);
                            final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
                            if (!opened && context.mounted) Navigator.of(context).pushNamed('/support');
                          },
                          child: Text(
                            '${t('fare_inquiry_contact')} · ${c.displayName}',
                          ),
                        ),
                    if (channels.isEmpty)
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/support'),
                        child: Text(t('fare_inquiry_contact')),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
