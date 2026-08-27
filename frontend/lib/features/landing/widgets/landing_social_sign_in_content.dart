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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.t(titleKey),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTokens.textPrimary,
          ),
        ),
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            errorMessage!,
            style: const TextStyle(color: AppTokens.error),
          ),
        ],
        const SizedBox(height: AppTokens.spaceMd),
        GoogleSignInButton(
          key: googleButtonKey,
          label: l10n.t('auth_google_continue'),
          locale: l10n.languageCode,
          loading: isLoading,
          onPressed: onGoogleSignInPressed,
        ),
        if (showKakaoButton) ...[
          const SizedBox(height: AppTokens.spaceSm),
          KakaoSignInButton(
            label: l10n.t('auth_kakao_continue'),
            loading: isLoading,
            onPressed: onKakaoSignInPressed,
          ),
        ],
        if (showLineButton) ...[
          const SizedBox(height: AppTokens.spaceSm),
          LineSignInButton(
            label: l10n.t('auth_line_continue'),
            loading: isLoading,
            onPressed: onLineSignInPressed,
          ),
        ],
      ],
    );
  }
}
