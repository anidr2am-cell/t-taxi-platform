import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../support/data/support_contact_api.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

class DriverSupportPage extends StatefulWidget {
  const DriverSupportPage({
    super.key,
    required this.api,
    ExternalUrlLauncher? launchExternal,
  }) : launchExternal = launchExternal ?? _launchExternal;

  final SupportContactDataSource api;
  final ExternalUrlLauncher launchExternal;

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  State<DriverSupportPage> createState() => _DriverSupportPageState();
}

class _DriverSupportPageState extends State<DriverSupportPage> {
  Uri? _lineUrl;
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lineUrl = await widget.api.getAdministratorLineUrl();
      if (mounted) setState(() => _lineUrl = lineUrl);
    } catch (_) {
      if (mounted) setState(() => _lineUrl = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLine() async {
    final uri = _lineUrl;
    if (uri == null || _opening) return;
    setState(() => _opening = true);
    final opened = await widget.launchExternal(uri);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).lineLaunchFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.contactAdministrator)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.support_agent,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.administratorEmergencyContact,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(l10n.administratorLineHelp, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_lineUrl == null)
              Column(
                children: [
                  Text(l10n.lineUnavailable, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
                ],
              )
            else
              FilledButton.icon(
                key: const Key('openAdministratorLine'),
                onPressed: _opening ? null : _openLine,
                icon: const Icon(Icons.open_in_new),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(l10n.openAdministratorLine),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              l10n.externalLineNotice,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
