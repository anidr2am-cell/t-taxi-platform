import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';

class LandingHeader extends StatelessWidget {
  final VoidCallback onLookup;

  const LandingHeader({super.key, required this.onLookup});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.watch<LocaleState>();
    final languageName = AppLocalizations.languageNames[locale.languageCode] ?? locale.languageCode;

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
            _LanguageButton(languageName: languageName, label: l10n.t('landing_language_label')),
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
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: AppTokens.textPrimary, size: 22),
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
                      const Icon(Icons.check, size: 18, color: AppTokens.primary)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.languageNames[code] ?? code),
                  ],
                ),
              ),
            )
            .toList(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, size: 18, color: AppTokens.primary),
                const SizedBox(width: 4),
                Text(
                  languageName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Icon(Icons.expand_more, size: 18, color: AppTokens.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
