import 'package:flutter/material.dart';

import '../../core/analytics/analytics_consent.dart';
import '../../core/analytics/analytics_consent_handler.dart';
import '../../core/analytics/analytics_consent_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';

/// Compact layout tokens for the bottom analytics consent banner.
abstract final class AnalyticsConsentBannerLayout {
  static const desktopBreakpoint = 600.0;
  static const mobilePadding = 12.0;
  static const desktopPadding = 16.0;
  static const titleFontSize = 14.0;
  static const bodyFontSize = 12.0;
  static const buttonFontSize = 12.0;
  static const buttonHeight = 36.0;
}

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
    _consentService =
        widget.consentService ?? AnalyticsConsentProvider.instance;
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
    final isDesktop =
        MediaQuery.sizeOf(context).width >=
        AnalyticsConsentBannerLayout.desktopBreakpoint;
    final padding = isDesktop
        ? AnalyticsConsentBannerLayout.desktopPadding
        : AnalyticsConsentBannerLayout.mobilePadding;

    final copy = _ConsentBannerCopy(l10n: l10n);
    final actions = _ConsentBannerActions(
      l10n: l10n,
      onDeny: () => _applyConsent(AnalyticsConsentStatus.denied),
      onAllow: () => _applyConsent(AnalyticsConsentStatus.granted),
      onPrivacy: () => Navigator.of(context).pushNamed('/privacy-policy'),
    );

    return Material(
      elevation: 8,
      color: AppTokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 12),
                    actions,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [copy, const SizedBox(height: 8), actions],
                ),
        ),
      ),
    );
  }
}

class _ConsentBannerCopy extends StatelessWidget {
  const _ConsentBannerCopy({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('analytics_consent_title'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AnalyticsConsentBannerLayout.titleFontSize,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.t('analytics_consent_body'),
          style: const TextStyle(
            color: AppTokens.textSecondary,
            fontSize: AnalyticsConsentBannerLayout.bodyFontSize,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ConsentBannerActions extends StatelessWidget {
  const _ConsentBannerActions({
    required this.l10n,
    required this.onDeny,
    required this.onAllow,
    required this.onPrivacy,
  });

  final AppLocalizations l10n;
  final VoidCallback onDeny;
  final VoidCallback onAllow;
  final VoidCallback onPrivacy;

  static ButtonStyle _textButtonStyle() {
    return TextButton.styleFrom(
      minimumSize: const Size(0, AnalyticsConsentBannerLayout.buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(
        fontSize: AnalyticsConsentBannerLayout.buttonFontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle _filledButtonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size(0, AnalyticsConsentBannerLayout.buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(
        fontSize: AnalyticsConsentBannerLayout.buttonFontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: onDeny,
          style: _textButtonStyle(),
          child: Text(l10n.t('analytics_consent_deny')),
        ),
        TextButton(
          onPressed: onPrivacy,
          style: _textButtonStyle(),
          child: Text(l10n.t('analytics_consent_privacy')),
        ),
        FilledButton(
          onPressed: onAllow,
          style: _filledButtonStyle(),
          child: Text(l10n.t('analytics_consent_allow')),
        ),
      ],
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
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.t('analytics_consent_body')),
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton(
                onPressed: () {
                  applyAnalyticsConsent(
                    service,
                    AnalyticsConsentStatus.granted,
                  );
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
              ),
            ],
          ),
        );
      },
    );
  }
}
