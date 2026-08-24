import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../config/kakao_auth_config.dart';
import '../controllers/auth_controller.dart';
import '../models/social_login_return_context.dart';
import 'google_sign_in_button.dart';
import 'kakao_sign_in_button.dart';

class BookingSocialLoginSection extends StatefulWidget {
  const BookingSocialLoginSection({
    super.key,
    this.authController,
    this.kakaoReturnContext,
    this.showKakaoButton,
  });

  final AuthController? authController;
  final SocialLoginReturnContext? kakaoReturnContext;
  final bool? showKakaoButton;

  @override
  State<BookingSocialLoginSection> createState() =>
      _BookingSocialLoginSectionState();
}

class _BookingSocialLoginSectionState extends State<BookingSocialLoginSection> {
  bool _dismissed = false;
  bool _initialLoginCaptured = false;
  bool _wasLoggedInAtMount = false;

  AuthController _resolveController(BuildContext context) {
    return widget.authController ?? AuthScope.of(context);
  }

  bool _shouldShowKakaoButton(AuthController controller) {
    if (widget.showKakaoButton != null) {
      return widget.showKakaoButton!;
    }
    return KakaoAuthConfig.isConfigured && widget.kakaoReturnContext != null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isInitialized || _dismissed) {
          return const SizedBox.shrink();
        }

        if (!_initialLoginCaptured) {
          _initialLoginCaptured = true;
          _wasLoggedInAtMount = controller.isLoggedIn;
        }

        if (controller.isLoggedIn) {
          if (_wasLoggedInAtMount && controller.hadPersistedSessionAtInit) {
            return const SizedBox.shrink();
          }
          return _ConnectedCard(
            l10n: context.l10n,
            displayName: controller.user!.displayLabel,
          );
        }

        return _PromptCard(
          l10n: context.l10n,
          isLoading: controller.isLoading,
          errorMessage: controller.errorMessage,
          showKakaoButton: _shouldShowKakaoButton(controller),
          onLater: () => setState(() => _dismissed = true),
          onGoogleSignInPressed: controller.isLoading
              ? null
              : () => controller.signInWithGoogle(),
          onKakaoSignInPressed: controller.isLoading ||
                  widget.kakaoReturnContext == null
              ? null
              : () => controller.beginKakaoSignIn(widget.kakaoReturnContext!),
        );
      },
    );
  }
}

class AuthScope extends InheritedWidget {
  const AuthScope({super.key, required this.controller, required super.child});

  final AuthController controller;

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope not found in widget tree');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(AuthScope oldWidget) =>
      oldWidget.controller != controller;
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.l10n,
    required this.isLoading,
    required this.errorMessage,
    required this.showKakaoButton,
    required this.onLater,
    required this.onGoogleSignInPressed,
    required this.onKakaoSignInPressed,
  });

  final AppLocalizations l10n;
  final bool isLoading;
  final String? errorMessage;
  final bool showKakaoButton;
  final VoidCallback onLater;
  final VoidCallback? onGoogleSignInPressed;
  final VoidCallback? onKakaoSignInPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.surfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('auth_social_login_title'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                l10n.t('auth_social_login_description'),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  height: 1.45,
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
              const SizedBox(height: AppTokens.spaceSm),
              TextButton(
                onPressed: isLoading ? null : onLater,
                child: Text(l10n.t('auth_social_login_later')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.l10n, required this.displayName});

  final AppLocalizations l10n;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final message = l10n
        .t('auth_social_login_connected')
        .replaceAll('{name}', displayName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.surfaceCard(
          backgroundColor: AppTokens.successLight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline, color: AppTokens.success),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
