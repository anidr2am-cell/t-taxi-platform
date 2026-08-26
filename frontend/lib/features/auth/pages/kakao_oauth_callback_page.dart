import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../booking/models/booking_create_result.dart';
import '../../booking/pages/booking_complete_page.dart';
import '../config/kakao_auth_config.dart';
import '../controllers/auth_controller.dart';
import '../models/kakao_oauth_callback_guard.dart';
import '../models/social_login_return_context.dart';
import '../services/kakao_oauth_callback_guard_storage.dart';
import '../services/kakao_oauth_callback_url.dart';
import '../services/kakao_oauth_page_reload.dart';
import '../widgets/booking_social_login_section.dart';

const kBookingCompleteRouteName = '/booking/complete';

@visibleForTesting
const kKakaoCallbackLoadingHintDelay = Duration(seconds: 8);

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
  const KakaoOAuthCallbackPage({
    super.key,
    required this.uri,
    this.guardStorage,
    this.loadingHintDelay = kKakaoCallbackLoadingHintDelay,
  });

  final Uri uri;
  final KakaoOAuthCallbackGuardStorage? guardStorage;
  final Duration loadingHintDelay;

  @override
  State<KakaoOAuthCallbackPage> createState() => _KakaoOAuthCallbackPageState();
}

class _KakaoOAuthCallbackPageState extends State<KakaoOAuthCallbackPage> {
  bool _started = false;
  bool _showSlowLoadingHint = false;
  Timer? _slowLoadingTimer;

  KakaoOAuthCallbackGuardStorage get _guardStorage =>
      widget.guardStorage ?? createKakaoOAuthCallbackGuardStorage();

  @override
  void initState() {
    super.initState();
    _slowLoadingTimer = Timer(widget.loadingHintDelay, () {
      if (!mounted) {
        return;
      }
      setState(() => _showSlowLoadingHint = true);
    });
  }

  @override
  void dispose() {
    _slowLoadingTimer?.cancel();
    super.dispose();
  }

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

    final oauthError = parseKakaoAuthorizationError(widget.uri);
    if (oauthError != null) {
      await _finishWithError(
        l10n.t('auth_kakao_callback_error'),
        null,
        authController,
      );
      return;
    }

    final code = parseKakaoAuthorizationCode(widget.uri);
    if (code == null) {
      final existingRecord = await _guardStorage.load();
      if (existingRecord != null) {
        await _handleProcessedReplay(
          existingRecord,
          l10n,
          authController,
        );
        return;
      }

      await _finishWithError(
        l10n.t('auth_kakao_callback_error'),
        null,
        authController,
      );
      return;
    }

    final existingRecord = await _guardStorage.load();
    if (existingRecord != null && existingRecord.code == code) {
      await _handleProcessedReplay(
        existingRecord,
        l10n,
        authController,
      );
      return;
    }

    await _guardStorage.save(
      KakaoOAuthCallbackGuardRecord(
        code: code,
        outcome: KakaoOAuthCallbackOutcome.pending,
      ),
    );

    final returnStorage = SocialLoginReturnStorage();
    final savedContext = await returnStorage.loadAndClear();
    final redirectUri = savedContext?.redirectUri ??
        KakaoAuthConfig.buildRedirectUri();

    await _guardStorage.save(
      KakaoOAuthCallbackGuardRecord(
        code: code,
        outcome: KakaoOAuthCallbackOutcome.pending,
        returnContext: savedContext,
      ),
    );

    await authController.completeSignInWithKakaoCode(
      code: code,
      redirectUri: redirectUri,
    );

    if (authController.isLoggedIn) {
      await _guardStorage.save(
        KakaoOAuthCallbackGuardRecord(
          code: code,
          outcome: KakaoOAuthCallbackOutcome.success,
          returnContext: savedContext,
        ),
      );
      if (!mounted) {
        return;
      }
      await _navigateToReturnContext(savedContext, authController);
      return;
    }

    await _guardStorage.save(
      KakaoOAuthCallbackGuardRecord(
        code: code,
        outcome: KakaoOAuthCallbackOutcome.failure,
        returnContext: savedContext,
      ),
    );

    if (!mounted) {
      return;
    }

    await _finishWithError(
      authController.errorMessage ?? l10n.t('auth_kakao_callback_error'),
      savedContext,
      authController,
    );
  }

  Future<void> _handleProcessedReplay(
    KakaoOAuthCallbackGuardRecord record,
    AppLocalizations l10n,
    AuthController authController,
  ) async {
    if (record.isSuccess || authController.isLoggedIn) {
      authController.setErrorMessage(null);
      if (!mounted) {
        return;
      }
      await _navigateToReturnContext(record.returnContext, authController);
      return;
    }

    if (record.isPending) {
      authController.setErrorMessage(null);
      if (!mounted) {
        return;
      }
      await _finishWithReplayNotice(
        l10n.t('auth_kakao_callback_already_processed'),
        record.returnContext,
        authController,
      );
      return;
    }

    authController.setErrorMessage(null);
    if (!mounted) {
      return;
    }
    await _finishWithReplayNotice(
      l10n.t('auth_kakao_callback_already_processed'),
      record.returnContext,
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

  Future<void> _finishWithReplayNotice(
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
    stripKakaoCallbackCodeFromBrowserUrl(widget.uri);

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
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: kBookingCompleteRouteName),
        builder: (_) => destination,
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_showSlowLoadingHint) ...[
                const SizedBox(height: AppTokens.spaceLg),
                Text(
                  l10n.t('auth_kakao_callback_slow_loading'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FilledButton(
                  key: const Key('kakao_callback_refresh_button'),
                  onPressed: reloadKakaoOAuthBrowserPage,
                  child: Text(l10n.t('auth_kakao_callback_refresh')),
                ),
              ],
            ],
          ),
        ),
      ),
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
