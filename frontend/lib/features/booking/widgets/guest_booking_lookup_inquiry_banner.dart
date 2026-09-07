import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

        final message = settings.message.trim();
        final channels = settings.channels;
        if (message.isEmpty && channels.isEmpty) {
          return const SizedBox.shrink();
        }

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
                if (message.isNotEmpty && channels.isNotEmpty)
                  const SizedBox(height: AppTokens.spaceSm),
                if (channels.isNotEmpty)
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      for (final channel in channels)
                        _ChannelIconButton(
                          channel: channel,
                          onTap: () => _openChannel(channel),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChannelIconButton extends StatelessWidget {
  const _ChannelIconButton({
    required this.channel,
    required this.onTap,
  });

  final ContactChannel channel;
  final VoidCallback onTap;

  static const _kakaoYellow = Color(0xFFFEE500);
  static const _lineGreen = Color(0xFF06C755);

  @override
  Widget build(BuildContext context) {
    final code = channel.code.toUpperCase();
    final isKakao = code == 'KAKAO';
    final isLine = code == 'LINE';
    if (!isKakao && !isLine) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: channel.displayName,
      child: Material(
        color: isKakao ? _kakaoYellow : _lineGreen,
        borderRadius: AppTokens.borderRadiusMd,
        child: InkWell(
          key: Key('guest_lookup_inquiry_channel_$code'),
          onTap: onTap,
          borderRadius: AppTokens.borderRadiusMd,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: isKakao
                  ? const KakaoBrandIcon(size: 24)
                  : const LineBrandIcon(size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
