import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/clipboard_writer.dart';
import '../../../widgets/app_ui.dart';
import '../models/contact_channel.dart';
import '../services/booking_contact_connection_service.dart';
import '../utils/contact_channel_url.dart';

const _handoffChannelCodes = {
  'KAKAO',
  'LINE',
  'WHATSAPP',
  'WECHAT',
  'TELEGRAM',
};

@visibleForTesting
List<ContactChannel> bookingHandoffChannels(
  List<ContactChannel> channels,
  String languageCode,
) {
  return orderContactChannels(
    channels
        .where((channel) => _handoffChannelCodes.contains(channel.code))
        .toList(),
    languageCode,
  );
}

@visibleForTesting
String bookingMessengerHandoffMessage(String bookingNumber) =>
    'T-Rider booking $bookingNumber';

class BookingMessengerHandoffSection extends StatefulWidget {
  const BookingMessengerHandoffSection({
    super.key,
    required this.bookingNumber,
    this.service,
    this.contactChannel,
  });

  final String bookingNumber;
  final String? contactChannel;
  final BookingContactConnectionService? service;

  @override
  State<BookingMessengerHandoffSection> createState() =>
      _BookingMessengerHandoffSectionState();
}

class _BookingMessengerHandoffSectionState
    extends State<BookingMessengerHandoffSection> {
  late final BookingContactConnectionService _service =
      widget.service ?? BookingContactConnectionService();
  List<ContactChannel> _channels = const [];
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    try {
      final channels = await _service.getPublicChannels();
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openChannel(ContactChannel channel) async {
    if (_opening) return;
    setState(() => _opening = true);

    final message = bookingMessengerHandoffMessage(widget.bookingNumber);
    if (channel.code == 'WECHAT') {
      await writeClipboardText(message);
      if (!mounted) return;
      setState(() => _opening = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.t('booking_contact_wechat')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.t('booking_wechat_qr_help')),
                const SizedBox(height: AppTokens.spaceSm),
                if (channel.qrImageUrl?.isNotEmpty == true)
                  Image.network(
                    channel.qrImageUrl!,
                    width: 280,
                    fit: BoxFit.contain,
                  ),
                if (channel.qrImageUrl?.isNotEmpty == true)
                  TextButton.icon(
                    onPressed: () async {
                      final uri = parseAllowedContactChannelUrl(
                        channel.qrImageUrl!,
                        allowHttp: allowHttpContactUrlsForEnvironment(),
                      );
                      if (uri != null)
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(context.l10n.t('booking_wechat_open_qr')),
                  ),
                SelectableText(message),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.t('support_close_button')),
            ),
          ],
        ),
      );
      return;
    }
    Uri? uri;
    if (channel.code == 'WHATSAPP') {
      final phone = channel.phoneNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (phone.isNotEmpty) {
        uri = parseAllowedContactChannelUrl(
          'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
          allowHttp: allowHttpContactUrlsForEnvironment(),
        );
      }
    } else {
      final raw = channel.addUrl?.trim() ?? '';
      if (raw.isNotEmpty) {
        uri = parseAllowedContactChannelUrl(
          raw,
          allowHttp: allowHttpContactUrlsForEnvironment(),
        );
      }
    }

    var launched = false;
    if (uri != null) {
      await writeClipboardText(message);
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    setState(() => _opening = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              launched
                  ? 'booking_messenger_handoff_copied'
                  : 'contact_connect_launch_failed',
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ordered = bookingHandoffChannels(_channels, l10n.languageCode);
    final channels = widget.contactChannel == null
        ? ordered
        : ordered.where((c) => c.code == widget.contactChannel).toList();
    if (!_loading && channels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.surfaceCard(
          backgroundColor: AppTokens.accentLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('booking_messenger_handoff_title'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                l10n.t('booking_messenger_handoff_description'),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              _Milestone(
                icon: Icons.check_circle_outline,
                label: l10n.t('booking_messenger_step_received'),
              ),
              _Milestone(
                icon: Icons.directions_car_outlined,
                label: l10n.t('booking_messenger_step_assigning'),
              ),
              _Milestone(
                icon: Icons.badge_outlined,
                label: l10n.t('booking_messenger_step_assigned'),
              ),
              _Milestone(
                icon: Icons.notifications_active_outlined,
                label: l10n.t('booking_messenger_step_departure'),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                for (final channel in channels) ...[
                  SizedBox(
                    height: 48,
                    child: FilledButton.tonalIcon(
                      key: Key('booking_handoff_${channel.code.toLowerCase()}'),
                      onPressed: _opening ? null : () => _openChannel(channel),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                        l10n
                            .t('booking_messenger_handoff_channel')
                            .replaceAll('{channel}', channel.displayName),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                ],
              Text(
                l10n.t('booking_messenger_handoff_optional'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Milestone extends StatelessWidget {
  const _Milestone({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppTokens.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
