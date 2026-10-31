import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/contact_channel.dart';
import '../services/booking_contact_connection_service.dart';
import 'fare_inquiry_card.dart';
import 'booking_messenger_icon.dart';
import '../utils/contact_channel_url.dart';

class PreferredSupportButton extends StatefulWidget {
  const PreferredSupportButton({
    super.key,
    this.chooseChannel = false,
    this.service,
    this.launchOverride,
  });
  final bool chooseChannel;
  final BookingContactConnectionService? service;
  final Future<bool> Function(Uri)? launchOverride;
  @override
  State<PreferredSupportButton> createState() => _PreferredSupportButtonState();
}

class _PreferredSupportButtonState extends State<PreferredSupportButton> {
  late final _channels = (widget.service ?? BookingContactConnectionService())
      .getPublicChannels();

  Future<bool> _launch(Uri uri) =>
      widget.launchOverride?.call(uri) ??
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _chooseChannel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final languageCode = context.l10n.languageCode;
    List<ContactChannel> channels;
    try {
      channels = orderContactChannels(await _channels, languageCode);
    } catch (_) {
      channels = [];
    }
    if (!mounted) return;
    if (channels.isEmpty) {
      Navigator.pushNamed(context, '/support');
      return;
    }
    final selected = await showModalBottomSheet<ContactChannel>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.t('support_contact_channels_title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              for (final channel in channels)
                ListTile(
                  key: ValueKey('booking-support-${channel.code}'),
                  leading: bookingMessengerIcon(channel.code),
                  title: Text(channel.displayName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheetContext, channel),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.code == 'WECHAT') {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.t('support_wechat_qr_dialog_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.t('support_wechat_qr_dialog_hint')),
                const SizedBox(height: AppTokens.spaceSm),
                if (selected.qrImageUrl?.isNotEmpty == true) ...[
                  Image.network(
                    selected.qrImageUrl!,
                    width: 280,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Text(context.l10n.t('ui_load_failed')),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final uri = parseAllowedContactChannelUrl(
                        selected.qrImageUrl!,
                        allowHttp: allowHttpContactUrlsForEnvironment(),
                      );
                      await _openUri(uri);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(context.l10n.t('booking_wechat_open_qr')),
                  ),
                ] else
                  Text(context.l10n.t('ui_load_failed')),
                if (selected.accountId?.isNotEmpty == true)
                  SelectableText(selected.accountId!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.t('close')),
            ),
          ],
        ),
      );
      return;
    }
    await _openUri(fareInquiryChannelUri(selected));
  }

  Future<void> _openUri(Uri? uri) async {
    bool opened = false;
    try {
      if (uri != null) opened = await _launch(uri);
    } catch (_) {
      /* Keep the draft on launch failure. */
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('contact_connect_launch_failed')),
        ),
      );
    }
  }

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
            widget.chooseChannel || channel == null
                ? context.l10n.t('landing_support_cta')
                : '${context.l10n.t('landing_support_cta')} · ${channel.displayName}',
          ),
          onPressed: () async {
            if (widget.chooseChannel) {
              await _chooseChannel();
              return;
            }
            final uri = channel == null ? null : fareInquiryChannelUri(channel);
            if (uri != null && await _launch(uri)) return;
            if (context.mounted) Navigator.pushNamed(context, '/support');
          },
        ),
      );
    },
  );
}
