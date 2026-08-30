import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import 'landing_auth_bottom_sheet.dart';
import 'landing_clickable_styles.dart';

class LandingHeader extends StatelessWidget {
  final VoidCallback onLookup;

  static const logoAssetPath = 'assets/images/logo.png';

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
            Flexible(child: _BrandBlock(subtitle: l10n.t('app_subtitle'))),
            const Spacer(),
            _AuthHeaderButton(l10n: l10n),
            _HeaderIconButton(
              buttonKey: const Key('landing_header_lookup_button'),
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

class _AuthHeaderButton extends StatelessWidget {
  const _AuthHeaderButton({required this.l10n, this.authController});

  final AppLocalizations l10n;
  final AuthController? authController;

  AuthController _resolveController(BuildContext context) {
    return authController ?? AuthScope.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isInitialized) {
          return const SizedBox.shrink();
        }

        final isLoggedIn = controller.isLoggedIn;
        if (!isLoggedIn) {
          return _HeaderIconButton(
            buttonKey: const Key('landing_header_auth_button'),
            tooltip: l10n.t('landing_login_sheet_title'),
            icon: Icons.person_outline,
            onPressed: () => showLandingAuthBottomSheet(context),
          );
        }

        return _LoggedInAuthHeaderButton(
          l10n: l10n,
          controller: controller,
        );
      },
    );
  }
}

enum _AuthHeaderMenuAction { account, myBookings }

class _LoggedInAuthHeaderButton extends StatelessWidget {
  const _LoggedInAuthHeaderButton({
    required this.l10n,
    required this.controller,
  });

  final AppLocalizations l10n;
  final AuthController controller;

  Future<void> _handleSelection(
    BuildContext context,
    _AuthHeaderMenuAction action,
  ) async {
    switch (action) {
      case _AuthHeaderMenuAction.account:
        await Navigator.of(context).pushNamed('/account');
      case _AuthHeaderMenuAction.myBookings:
        await Navigator.of(context).pushNamed('/my-bookings');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: l10n.t('landing_my_bookings_button'),
      child: PopupMenuButton<_AuthHeaderMenuAction>(
        key: const Key('landing_header_auth_button'),
        tooltip: l10n.t('landing_my_bookings_button'),
        offset: const Offset(0, 44),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
        onSelected: (action) => _handleSelection(context, action),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const Key('landing_header_account_menu'),
            value: _AuthHeaderMenuAction.account,
            child: Text(l10n.t('landing_header_account_menu')),
          ),
          PopupMenuItem(
            key: const Key('landing_header_my_bookings_menu'),
            value: _AuthHeaderMenuAction.myBookings,
            child: Text(l10n.t('landing_header_my_bookings_menu')),
          ),
        ],
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconButton.filledTonal(
            onPressed: null,
            style: LandingClickableStyles.iconButtonStyle(),
            icon: const Icon(Icons.person, size: 22),
          ),
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  final String subtitle;

  const _BrandBlock({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;
    final logoHeight = isCompact ? 34.0 : 42.0;
    final logoMaxWidth = isCompact ? 116.0 : 152.0;

    return Semantics(
      header: true,
      label: 'T-Rider',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: logoMaxWidth),
        child: Column(
          key: const Key('landing_brand_block'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: logoHeight,
              width: logoMaxWidth,
              child: Image.asset(
                LandingHeader.logoAssetPath,
                key: const Key('landing_header_logo'),
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: 'T-Rider',
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isCompact ? 10 : 11,
                color: AppTokens.textSecondary,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    this.buttonKey,
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
            key: buttonKey,
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
