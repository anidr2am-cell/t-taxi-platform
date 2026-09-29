import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/models/contact_channel.dart';
import '../../booking/services/booking_contact_connection_service.dart';
import '../../booking/utils/contact_channel_url.dart';

typedef DriverSupportUrlLauncher = Future<bool> Function(Uri uri);

class DriverSupportPage extends StatefulWidget {
  const DriverSupportPage({
    super.key,
    this.contactService,
    this.launchUrlOverride,
  });

  final BookingContactConnectionService? contactService;
  final DriverSupportUrlLauncher? launchUrlOverride;

  @override
  State<DriverSupportPage> createState() => _DriverSupportPageState();
}

class _DriverSupportPageState extends State<DriverSupportPage> {
  late final Future<ContactChannel?> _lineFuture = _loadLineChannel();
  bool _opening = false;

  BookingContactConnectionService get _contactService =>
      widget.contactService ?? BookingContactConnectionService();

  Future<ContactChannel?> _loadLineChannel() async {
    final channels = await _contactService.getPublicChannels();
    for (final channel in channels) {
      if (channel.code.toUpperCase() == 'LINE' &&
          (channel.addUrl?.trim().isNotEmpty ?? false)) {
        return channel;
      }
    }
    return null;
  }

  Future<void> _openLine(ContactChannel channel) async {
    if (_opening) return;
    final uri = parseAllowedContactChannelUrl(
      channel.addUrl ?? '',
      allowHttp: allowHttpContactUrlsForEnvironment(),
    );
    if (uri == null) {
      _showMessage(context.l10n.t('driver_support_line_unavailable'));
      return;
    }

    setState(() => _opening = true);
    final launch = widget.launchUrlOverride ?? _launchExternal;
    bool launched = false;
    try {
      launched = await launch(uri);
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!launched) {
      _showMessage(context.l10n.t('driver_support_line_launch_failed'));
    }
  }

  Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_support_title'))),
      body: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          AppUi.adminDetailSection(
            context: context,
            title: l10n.t('driver_support_inquiry'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.support_agent,
                  color: AppTokens.primary,
                  size: 52,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  l10n.t('driver_support_line_help'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                FutureBuilder<ContactChannel?>(
                  future: _lineFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final channel = snapshot.data;
                    if (snapshot.hasError || channel == null) {
                      return Text(
                        l10n.t('driver_support_line_unavailable'),
                        key: const Key('driver_admin_line_unavailable'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTokens.error),
                      );
                    }
                    return SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        key: const Key('driver_admin_line_contact_button'),
                        onPressed: _opening ? null : () => _openLine(channel),
                        icon: _opening
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.chat_bubble_outline),
                        label: Text(l10n.t('driver_support_open_line')),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  l10n.t('driver_support_external_app_notice'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
