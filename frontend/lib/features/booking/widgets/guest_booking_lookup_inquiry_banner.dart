import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/widgets/social_brand_icons.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';
import '../models/contact_channel.dart';
import '../models/guest_lookup_inquiry_settings.dart';
import '../utils/contact_channel_url.dart';

typedef GuestLookupInquiryUrlLauncher = Future<bool> Function(Uri uri);

class GuestBookingLookupInquiryBanner extends StatefulWidget {
  const GuestBookingLookupInquiryBanner({
    super.key,
    this.api = const PlatformSettingsApiService(),
    this.launchUrlOverride,
  });

  final PlatformSettingsApiService api;
  final GuestLookupInquiryUrlLauncher? launchUrlOverride;

  @override
  State<GuestBookingLookupInquiryBanner> createState() =>
      _GuestBookingLookupInquiryBannerState();
}

class _GuestBookingLookupInquiryBannerState
    extends State<GuestBookingLookupInquiryBanner> {
  late Future<GuestLookupInquirySettings> _settingsFuture =
      _loadSettings();

  Future<GuestLookupInquirySettings> _loadSettings() async {
    final data = await widget.api.getGuestLookupInquiry();
    return GuestLookupInquirySettings.fromJson(data);
  }

  Future<void> _openChannel(ContactChannel channel) async {
    final url = channel.addUrl?.trim();
    if (url == null || url.isEmpty) return;
    final uri = parseAllowedContactChannelUrl(
      url,
      allowHttp: allowHttpContactUrlsForEnvironment(),
    );
    if (uri == null) return;
    final launch = widget.launchUrlOverride ?? _defaultLaunchUrl;
    await launch(uri);
  }

  Future<bool> _defaultLaunchUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GuestLookupInquirySettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        final settings = snapshot.data;
        if (settings == null || !settings.shouldShowBanner) {
          return const SizedBox.shrink();
        }

        final l10n = context.l10n;
        final message = settings.message.trim();
        final channels = settings.channels;
        if (message.isEmpty && channels.isEmpty) {
          return const SizedBox.shrink();
        }
        final showChannelHint = channels.isNotEmpty && message.isEmpty;

        return KeyedSubtree(
          key: const Key('guest_lookup_inquiry_banner'),
          child: AppUi.surfaceCard(
            backgroundColor: AppTokens.infoLight,
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTokens.textPrimary,
                      height: 1.45,
                    ),
                  ),
                if (showChannelHint) ...[
                  if (message.isNotEmpty) const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    l10n.t('guest_lookup_inquiry_channels_hint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
                if (channels.isNotEmpty) ...[
                  if (message.isNotEmpty || showChannelHint)
                    const SizedBox(height: AppTokens.spaceSm),
                  Wrap(
                    spacing: AppTokens.spaceMd,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      for (final channel in channels)
                        _ChannelIconButton(
                          channel: channel,
                          label: _channelLabel(l10n, channel.code),
                          onTap: () => _openChannel(channel),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _channelLabel(AppLocalizations l10n, String code) {
    switch (code.toUpperCase()) {
      case 'KAKAO':
        return l10n.t('guest_lookup_inquiry_channel_kakao');
      case 'LINE':
        return l10n.t('guest_lookup_inquiry_channel_line');
      default:
        return code;
    }
  }
}

class _ChannelIconButton extends StatelessWidget {
  const _ChannelIconButton({
    required this.channel,
    required this.label,
    required this.onTap,
  });

  final ContactChannel channel;
  final String label;
  final VoidCallback onTap;

  static const _iconSize = 48.0;
  static const _columnWidth = 72.0;

  @override
  Widget build(BuildContext context) {
    final code = channel.code.toUpperCase();
    final isKakao = code == 'KAKAO';
    final isLine = code == 'LINE';
    if (!isKakao && !isLine) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: Key('guest_lookup_inquiry_channel_$code'),
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusMd,
        child: SizedBox(
          width: _columnWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              isKakao
                  ? const KakaoBrandIcon(
                      size: _iconSize,
                      style: SocialBrandIconStyle.appIcon,
                    )
                  : const LineBrandIcon(
                      size: _iconSize,
                      style: SocialBrandIconStyle.appIcon,
                    ),
              const SizedBox(height: 4),
              Text(
                label,
                key: Key('guest_lookup_inquiry_channel_label_$code'),
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
