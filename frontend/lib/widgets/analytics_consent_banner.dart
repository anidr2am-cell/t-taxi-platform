import 'package:flutter/material.dart';

import '../../core/analytics/analytics_consent.dart';
import '../../core/analytics/analytics_consent_handler.dart';
import '../../core/analytics/analytics_consent_provider.dart';
import '../../l10n/app_localizations.dart';import '../../theme/app_tokens.dart';

class AnalyticsConsentBanner extends StatefulWidget {
  const AnalyticsConsentBanner({
    super.key,
    this.consentService,
    this.onChanged,
  });

  final AnalyticsConsentService? consentService;
  final VoidCallback? onChanged;

  @override
  State<AnalyticsConsentBanner> createState() => _AnalyticsConsentBannerState();
}

class _AnalyticsConsentBannerState extends State<AnalyticsConsentBanner> {
  late AnalyticsConsentService _consentService;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _consentService = widget.consentService ?? AnalyticsConsentProvider.instance;
  }

  void _applyConsent(AnalyticsConsentStatus status) {
    applyAnalyticsConsent(_consentService, status);
    widget.onChanged?.call();
    setState(() => _showSettings = false);
  }
  @override
  Widget build(BuildContext context) {
    if (!_consentService.needsPrompt && !_showSettings) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    return Material(
      elevation: 8,
      color: AppTokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            AppTokens.spaceSm,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('analytics_consent_title'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                l10n.t('analytics_consent_body'),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceXs,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _applyConsent(AnalyticsConsentStatus.denied),
                    child: Text(l10n.t('analytics_consent_deny')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/privacy-policy'),
                    child: Text(l10n.t('analytics_consent_privacy')),
                  ),
                  FilledButton(
                    onPressed: () => _applyConsent(AnalyticsConsentStatus.granted),
                    child: Text(l10n.t('analytics_consent_allow')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnalyticsConsentSettingsButton extends StatelessWidget {
  const AnalyticsConsentSettingsButton({super.key, this.consentService});

  final AnalyticsConsentService? consentService;

  @override
  Widget build(BuildContext context) {
    final service = consentService ?? AnalyticsConsentProvider.instance;
    return TextButton(
      onPressed: () => _showSettingsSheet(context, service),
      child: Text(context.l10n.t('analytics_consent_settings')),
    );
  }

  Future<void> _showSettingsSheet(
    BuildContext context,
    AnalyticsConsentService service,
  ) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('analytics_consent_settings_title'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.t('analytics_consent_body')),
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton(
                onPressed: () {
                  applyAnalyticsConsent(service, AnalyticsConsentStatus.granted);
                  Navigator.of(context).pop();
                },
                child: Text(l10n.t('analytics_consent_allow')),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              OutlinedButton(
                onPressed: () {
                  applyAnalyticsConsent(service, AnalyticsConsentStatus.denied);
                  Navigator.of(context).pop();
                },
                child: Text(l10n.t('analytics_consent_deny')),
              ),            ],
          ),
        );
      },
    );
  }
}
