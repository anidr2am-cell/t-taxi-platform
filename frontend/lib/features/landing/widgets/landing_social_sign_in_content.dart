import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../auth/widgets/google_sign_in_button.dart';
import '../../auth/widgets/kakao_sign_in_button.dart';
import '../../auth/widgets/line_sign_in_button.dart';

/// Shared Google/Kakao/LINE sign-in controls for landing surfaces.
class LandingSocialSignInContent extends StatelessWidget {
  const LandingSocialSignInContent({
    super.key,
    required this.l10n,
    required this.isLoading,
    required this.errorMessage,
    required this.showKakaoButton,
    required this.showLineButton,
    required this.onGoogleSignInPressed,
    required this.onKakaoSignInPressed,
    required this.onLineSignInPressed,
    this.titleKey = 'landing_login_title',
    this.googleButtonKey = const Key('landing_google_sign_in'),
    this.showSupportLink = false,
  });

  final AppLocalizations l10n;
  final bool isLoading;
  final String? errorMessage;
  final bool showKakaoButton;
  final bool showLineButton;
  final VoidCallback? onGoogleSignInPressed;
  final VoidCallback? onKakaoSignInPressed;
  final VoidCallback? onLineSignInPressed;
  final String titleKey;
  final Key googleButtonKey;
  final bool showSupportLink;

  static const _buttonSpacing = 12.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.t(titleKey),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTokens.textPrimary,
          ),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTokens.error),
          ),
          const SizedBox(height: AppTokens.spaceLg),
        ],
        Text(
          l10n.t('auth_login_provider_hint'),
          key: const Key('auth_login_provider_hint'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        GoogleSignInButton(
          key: googleButtonKey,
          label: l10n.t('auth_google_continue'),
          locale: l10n.languageCode,
          loading: isLoading,
          onPressed: onGoogleSignInPressed,
        ),
        if (showKakaoButton) ...[
          const SizedBox(height: _buttonSpacing),
          KakaoSignInButton(
            label: l10n.t('auth_kakao_continue'),
            loading: isLoading,
            onPressed: onKakaoSignInPressed,
          ),
        ],
        if (showLineButton) ...[
          const SizedBox(height: _buttonSpacing),
          LineSignInButton(
            label: l10n.t('auth_line_continue'),
            loading: isLoading,
            onPressed: onLineSignInPressed,
          ),
        ],
        if (showSupportLink) ...[
          const SizedBox(height: AppTokens.spaceLg),
          _SupportLinkRow(l10n: l10n),
        ],
      ],
    );
  }
}

class _SupportLinkRow extends StatelessWidget {
  const _SupportLinkRow({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('landing_login_support_link'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(
          l10n.t('landing_login_support_prompt'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTokens.textSecondary,
          ),
        ),
        TextButton(
          key: const Key('landing_login_support_button'),
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/support');
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(l10n.t('landing_login_support_link')),
        ),
      ],
    );
  }
}
