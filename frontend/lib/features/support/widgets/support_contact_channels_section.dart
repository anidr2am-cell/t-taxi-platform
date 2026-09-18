import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/widgets/social_brand_icons.dart';
import '../../booking/models/contact_channel.dart';
import '../../booking/services/booking_contact_connection_service.dart';
import '../../booking/utils/contact_channel_url.dart';

typedef SupportContactUrlLauncher = Future<bool> Function(Uri uri);

class SupportContactChannelsSection extends StatefulWidget {
  const SupportContactChannelsSection({
    super.key,
    this.contactService,
    this.launchUrlOverride,
  });

  final BookingContactConnectionService? contactService;
  final SupportContactUrlLauncher? launchUrlOverride;

  @override
  State<SupportContactChannelsSection> createState() =>
      _SupportContactChannelsSectionState();
}

class _SupportContactChannelsSectionState
    extends State<SupportContactChannelsSection> {
  late final Future<List<ContactChannel>> _channelsFuture;

  BookingContactConnectionService get _service =>
      widget.contactService ?? BookingContactConnectionService();

  @override
  void initState() {
    super.initState();
    _channelsFuture = _loadChannels();
  }

  Future<List<ContactChannel>> _loadChannels() async {
    try {
      return await _service.getPublicChannels();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openChannel(ContactChannel channel) async {
    final l10n = context.l10n;
    final code = channel.code.toUpperCase();

    if (code == 'WECHAT') {
      await _showWeChatQrDialog(channel);
      return;
    }

    Uri? uri;
    switch (code) {
      case 'WHATSAPP':
        final phone = channel.phoneNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (phone.isEmpty) return;
        uri = parseAllowedContactChannelUrl(
          'https://wa.me/$phone',
          allowHttp: allowHttpContactUrlsForEnvironment(),
        );
        break;
      case 'LINE':
      case 'KAKAO':
        final url = channel.addUrl?.trim();
        if (url == null || url.isEmpty) return;
        uri = parseAllowedContactChannelUrl(
          url,
          allowHttp: allowHttpContactUrlsForEnvironment(),
        );
        break;
      default:
        return;
    }

    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('contact_connect_unsafe_url'))),
      );
      return;
    }

    final launch = widget.launchUrlOverride ?? _defaultLaunchUrl;
    final launched = await launch(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('contact_connect_launch_failed'))),
      );
    }
  }

  Future<bool> _defaultLaunchUrl(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _showWeChatQrDialog(ContactChannel channel) async {
    final l10n = context.l10n;
    final qrUrl = channel.qrImageUrl?.trim();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('support_wechat_qr_dialog_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.t('support_wechat_qr_dialog_hint'),
              style: const TextStyle(height: 1.45),
            ),
            if (qrUrl != null && qrUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: AppTokens.borderRadiusMd,
                child: Image.network(
                  qrUrl,
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => const SizedBox(
                    width: 180,
                    height: 180,
                    child: Icon(Icons.qr_code_2, size: 72),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('support_close_button')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;

    return FutureBuilder<List<ContactChannel>>(
      future: _channelsFuture,
      builder: (context, snapshot) {
        final channels = orderContactChannels(snapshot.data ?? const [], locale);
        if (channels.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppUi.sectionHeader(
              context,
              title: l10n.t('support_contact_channels_title'),
              subtitle: l10n.t('support_contact_channels_hint'),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppTokens.spaceMd,
              runSpacing: AppTokens.spaceMd,
              children: [
                for (final channel in channels)
                  _ContactChannelButton(
                    channel: channel,
                    onTap: () => _openChannel(channel),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ContactChannelButton extends StatelessWidget {
  const _ContactChannelButton({
    required this.channel,
    required this.onTap,
  });

  final ContactChannel channel;
  final VoidCallback onTap;

  static const _iconSize = 48.0;
  static const _columnWidth = 72.0;

  @override
  Widget build(BuildContext context) {
    final code = channel.code.toUpperCase();

    return Semantics(
      button: true,
      label: channel.displayName,
      child: InkWell(
        key: Key('support_contact_channel_$code'),
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusMd,
        child: SizedBox(
          width: _columnWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChannelIcon(code: code, size: _iconSize),
              const SizedBox(height: 4),
              Text(
                channel.displayName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelIcon extends StatelessWidget {
  const _ChannelIcon({required this.code, required this.size});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (code) {
      case 'KAKAO':
        return KakaoBrandIcon(
          size: size,
          style: SocialBrandIconStyle.appIcon,
        );
      case 'LINE':
        return LineBrandIcon(
          size: size,
          style: SocialBrandIconStyle.appIcon,
        );
      case 'WHATSAPP':
        return WhatsappBrandIcon(size: size);
      case 'WECHAT':
        return WechatBrandIcon(size: size);
      default:
        return Icon(Icons.chat_bubble_outline, size: size);
    }
  }
}
