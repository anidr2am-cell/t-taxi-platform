import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../auth/config/kakao_auth_config.dart';
import '../../auth/config/line_auth_config.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/social_login_return_context.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import 'landing_social_sign_in_content.dart';

Future<void> showLandingAuthBottomSheet(BuildContext context) {
  final controller = AuthScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => AuthScope(
      controller: controller,
      child: LandingAuthBottomSheet(authController: controller),
    ),
  );
}

class LandingAuthBottomSheet extends StatefulWidget {
  const LandingAuthBottomSheet({super.key, this.authController});

  final AuthController? authController;

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

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final l10n = context.l10n;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          key: const Key('landing_auth_bottom_sheet'),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: LandingSocialSignInContent(
            l10n: l10n,
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            showKakaoButton: KakaoAuthConfig.isConfigured,
            showLineButton: LineAuthConfig.isConfigured,
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
        );
      },
    );
  }
}
