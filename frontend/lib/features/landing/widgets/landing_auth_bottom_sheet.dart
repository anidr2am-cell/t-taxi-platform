import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../auth/config/kakao_auth_config.dart';
import '../../auth/config/line_auth_config.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/social_login_return_context.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import 'landing_header.dart';
import 'landing_social_sign_in_content.dart';

enum LandingAuthPresentation { bottomSheet, dialog }

const _desktopDialogBreakpoint = 768.0;

Future<void> showLandingAuthBottomSheet(BuildContext context) {
  final controller = AuthScope.of(context);
  final width = MediaQuery.sizeOf(context).width;

  if (width >= _desktopDialogBreakpoint) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (dialogContext) => AuthScope(
        controller: controller,
        child: Dialog(
          backgroundColor: AppTokens.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: LandingAuthBottomSheet(
              authController: controller,
              presentation: LandingAuthPresentation.dialog,
            ),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    isDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    backgroundColor: AppTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusLg)),
    ),
    builder: (sheetContext) => AuthScope(
      controller: controller,
      child: LandingAuthBottomSheet(
        authController: controller,
        presentation: LandingAuthPresentation.bottomSheet,
      ),
    ),
  );
}

class LandingAuthBottomSheet extends StatefulWidget {
  const LandingAuthBottomSheet({
    super.key,
    this.authController,
    this.presentation = LandingAuthPresentation.bottomSheet,
  });

  final AuthController? authController;
  final LandingAuthPresentation presentation;

  @override
  State<LandingAuthBottomSheet> createState() => _LandingAuthBottomSheetState();
}

class _LandingAuthBottomSheetState extends State<LandingAuthBottomSheet> {
  AuthController? _controller;

  AuthController _resolveController(BuildContext context) {
    return widget.authController ?? AuthScope.of(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _resolveController(context);
    if (_controller != controller) {
      _controller?.removeListener(_handleAuthChanged);
      _controller = controller;
      _controller!.addListener(_handleAuthChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (_controller?.isLoggedIn == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _closeSheet() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final l10n = context.l10n;
    final isBottomSheet =
        widget.presentation == LandingAuthPresentation.bottomSheet;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          key: const Key('landing_auth_bottom_sheet'),
          padding: EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            isBottomSheet ? AppTokens.spaceSm : AppTokens.spaceLg,
            AppTokens.spaceMd,
            AppTokens.spaceLg +
                (isBottomSheet ? MediaQuery.viewInsetsOf(context).bottom : 0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isBottomSheet) ...[
                Center(
                  child: Container(
                    key: const Key('landing_auth_sheet_handle'),
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: AppTokens.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 40,
                    child: Image.asset(
                      LandingHeader.logoAssetPath,
                      key: const Key('landing_auth_sheet_logo'),
                      fit: BoxFit.contain,
                      semanticLabel: 'T-Rider',
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.local_taxi_outlined,
                          size: 32,
                          color: AppTokens.primary,
                        );
                      },
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      key: const Key('landing_auth_sheet_close'),
                      tooltip: l10n.t('landing_login_sheet_close'),
                      onPressed: _closeSheet,
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        foregroundColor: AppTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceLg),
              LandingSocialSignInContent(
                l10n: l10n,
                isLoading: controller.isLoading,
                errorMessage: controller.errorMessage,
                showKakaoButton: KakaoAuthConfig.isConfigured,
                showLineButton: LineAuthConfig.isConfigured,
                showSupportLink: true,
                titleKey: 'landing_login_sheet_title',
                googleButtonKey: const Key('landing_sheet_google_sign_in'),
                onGoogleSignInPressed: controller.isLoading
                    ? null
                    : () => controller.signInWithGoogle(),
                onKakaoSignInPressed: controller.isLoading
                    ? null
                    : () => controller.beginKakaoSignIn(
                          SocialLoginReturnContext.fromLanding(),
                        ),
                onLineSignInPressed: controller.isLoading
                    ? null
                    : () => controller.beginLineSignIn(
                          SocialLoginReturnContext.fromLandingForLine(),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}
