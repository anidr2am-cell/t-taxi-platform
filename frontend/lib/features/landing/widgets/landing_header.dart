import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import 'landing_clickable_styles.dart';

class LandingHeader extends StatelessWidget {
  final VoidCallback onLookup;

  const LandingHeader({super.key, required this.onLookup});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.watch<LocaleState>();
    final languageName =
        AppLocalizations.languageNames[locale.languageCode] ??
        locale.languageCode;

    return Container(
      color: AppTokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Semantics(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.t('app_title'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.primaryDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    l10n.t('app_subtitle'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTokens.textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _HeaderIconButton(
              tooltip: l10n.t('landing_booking_lookup_action'),
              icon: Icons.search_outlined,
              onPressed: onLookup,
            ),
            _LanguageButton(
              languageName: languageName,
              label: l10n.t('landing_language_label'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconButton.filledTonal(
            key: const Key('landing_header_lookup_button'),
            onPressed: onPressed,
            style: LandingClickableStyles.iconButtonStyle(),
            icon: Icon(icon, size: 22),
          ),
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String languageName;
  final String label;

  const _LanguageButton({required this.languageName, required this.label});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleState>();

    return Semantics(
      button: true,
      label: label,
      child: PopupMenuButton<String>(
        tooltip: label,
        offset: const Offset(0, 44),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
        onSelected: (code) => context.read<LocaleState>().setLanguage(code),
        itemBuilder: (context) => AppLocalizations.supportedLanguages
            .map(
              (code) => PopupMenuItem(
                value: code,
                child: Row(
                  children: [
                    if (locale.languageCode == code)
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: AppTokens.primary,
                      )
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.languageNames[code] ?? code),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          key: const Key('landing_language_button'),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: LandingClickableStyles.background,
            borderRadius: AppTokens.borderRadiusMd,
            border: Border.all(color: LandingClickableStyles.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.language,
                size: 18,
                color: LandingClickableStyles.icon,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  languageName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more,
                size: 18,
                color: AppTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
