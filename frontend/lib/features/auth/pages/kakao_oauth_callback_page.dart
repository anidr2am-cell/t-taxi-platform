import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../booking/models/booking_create_result.dart';
import '../../booking/pages/booking_complete_page.dart';
import '../config/kakao_auth_config.dart';
import '../controllers/auth_controller.dart';
import '../models/social_login_return_context.dart';
import '../widgets/booking_social_login_section.dart';

@visibleForTesting
Route<dynamic>? buildKakaoOAuthCallbackRoute(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '');
  if (uri == null || uri.path != '/auth/kakao/callback') {
    return null;
  }

  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => KakaoOAuthCallbackPage(uri: uri),
  );
}

class KakaoOAuthCallbackPage extends StatefulWidget {
  const KakaoOAuthCallbackPage({super.key, required this.uri});

  final Uri uri;

  @override
  State<KakaoOAuthCallbackPage> createState() => _KakaoOAuthCallbackPageState();
}

class _KakaoOAuthCallbackPageState extends State<KakaoOAuthCallbackPage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleCallback());
    });
  }

  Future<void> _handleCallback() async {
    final l10n = context.l10n;
    final authController = AuthScope.of(context);
    final returnStorage = SocialLoginReturnStorage();
    final savedContext = await returnStorage.loadAndClear();
    final redirectUri = savedContext?.redirectUri ??
        KakaoAuthConfig.buildRedirectUri();

    final oauthError = parseKakaoAuthorizationError(widget.uri);
    if (oauthError != null) {
      await _finishWithError(
        l10n.t('auth_kakao_callback_error'),
        savedContext,
        authController,
      );
      return;
    }

    final code = parseKakaoAuthorizationCode(widget.uri);
    if (code == null) {
      await _finishWithError(
        l10n.t('auth_kakao_callback_error'),
        savedContext,
        authController,
      );
      return;
    }

    await authController.completeSignInWithKakaoCode(
      code: code,
      redirectUri: redirectUri,
    );

    if (!mounted) {
      return;
    }

    if (authController.isLoggedIn) {
      await _navigateToReturnContext(savedContext, authController);
      return;
    }

    await _finishWithError(
      authController.errorMessage ?? l10n.t('auth_kakao_callback_error'),
      savedContext,
      authController,
    );
  }

  Future<void> _finishWithError(
    String message,
    SocialLoginReturnContext? savedContext,
    AuthController authController,
  ) async {
    authController.setErrorMessage(message);
    await _navigateToReturnContext(savedContext, authController);
  }

  Future<void> _navigateToReturnContext(
    SocialLoginReturnContext? savedContext,
    AuthController authController,
  ) async {
    if (!mounted) {
      return;
    }

    final destination = savedContext == null
        ? const _KakaoCallbackFallbackPage()
        : BookingCompletePage(
            authController: authController,
            result: savedContext.result,
            serviceLabel: savedContext.serviceLabel,
            origin: savedContext.origin,
            destination: savedContext.destination,
            serviceTypeCode: savedContext.serviceTypeCode,
            originAirportCode: savedContext.originAirportCode,
            nameSignRequested: savedContext.nameSignRequested,
            customerPhone: savedContext.customerPhone,
            scheduledPickupAt: savedContext.scheduledPickupAt,
            selectedVehicle: savedContext.selectedVehicle,
            enableCustomerTools: savedContext.enableCustomerTools,
          );

    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => destination),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _KakaoCallbackFallbackPage extends StatelessWidget {
  const _KakaoCallbackFallbackPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T-Rider')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Text(
            context.l10n.t('auth_kakao_callback_error'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
