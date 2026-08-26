import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../booking/pages/booking_complete_page.dart';
import '../config/line_auth_config.dart';
import '../controllers/auth_controller.dart';
import '../models/line_oauth_callback_guard.dart';
import '../models/line_oauth_state_storage.dart';
import '../models/social_login_return_context.dart';
import '../services/line_oauth_callback_guard_storage.dart';
import '../services/line_oauth_callback_url.dart';
import '../services/line_oauth_page_reload.dart';
import '../services/line_oauth_state_storage.dart';
import '../widgets/booking_social_login_section.dart';
import 'kakao_oauth_callback_page.dart';

@visibleForTesting
const kLineCallbackLoadingHintDelay = Duration(seconds: 8);

@visibleForTesting
Route<dynamic>? buildLineOAuthCallbackRoute(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '');
  if (uri == null || uri.path != '/auth/line/callback') {
    return null;
  }

  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => LineOAuthCallbackPage(uri: uri),
  );
}

class LineOAuthCallbackPage extends StatefulWidget {
  const LineOAuthCallbackPage({
    super.key,
    required this.uri,
    this.guardStorage,
    this.stateStorage,
    this.loadingHintDelay = kLineCallbackLoadingHintDelay,
  });

  final Uri uri;
  final LineOAuthCallbackGuardStorage? guardStorage;
  final LineOAuthStateStorage? stateStorage;
  final Duration loadingHintDelay;

  @override
  State<LineOAuthCallbackPage> createState() => _LineOAuthCallbackPageState();
}

class _LineOAuthCallbackPageState extends State<LineOAuthCallbackPage> {
  bool _started = false;
  bool _showSlowLoadingHint = false;
  Timer? _slowLoadingTimer;

  LineOAuthCallbackGuardStorage get _guardStorage =>
      widget.guardStorage ?? createLineOAuthCallbackGuardStorage();

  LineOAuthStateStorage get _stateStorage =>
      widget.stateStorage ?? createLineOAuthStateStorage();

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

    final oauthError = parseLineAuthorizationError(widget.uri);
    if (oauthError != null) {
      await _finishWithError(
        l10n.t('auth_line_callback_error'),
        null,
        authController,
      );
      return;
    }

    final code = parseLineAuthorizationCode(widget.uri);
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
        l10n.t('auth_line_callback_error'),
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

    final returnedState = parseLineAuthorizationState(widget.uri);
    final expectedState = await _stateStorage.loadAndClear();
    if (returnedState == null ||
        expectedState == null ||
        returnedState != expectedState) {
      final savedContext = await SocialLoginReturnStorage().load();
      await _finishWithError(
        l10n.t('auth_line_callback_state_mismatch'),
        savedContext,
        authController,
      );
      return;
    }

    await _guardStorage.save(
      LineOAuthCallbackGuardRecord(
        code: code,
        outcome: LineOAuthCallbackOutcome.pending,
      ),
    );

    final returnStorage = SocialLoginReturnStorage();
    final savedContext = await returnStorage.loadAndClear();
    final redirectUri =
        savedContext?.redirectUri ?? LineAuthConfig.buildRedirectUri();

    await _guardStorage.save(
      LineOAuthCallbackGuardRecord(
        code: code,
        outcome: LineOAuthCallbackOutcome.pending,
        returnContext: savedContext,
      ),
    );

    await authController.completeSignInWithLineCode(
      code: code,
      redirectUri: redirectUri,
    );

    if (authController.isLoggedIn) {
      await _guardStorage.save(
        LineOAuthCallbackGuardRecord(
          code: code,
          outcome: LineOAuthCallbackOutcome.success,
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
      LineOAuthCallbackGuardRecord(
        code: code,
        outcome: LineOAuthCallbackOutcome.failure,
        returnContext: savedContext,
      ),
    );

    if (!mounted) {
      return;
    }

    await _finishWithError(
      authController.errorMessage ?? l10n.t('auth_line_callback_error'),
      savedContext,
      authController,
    );
  }

  Future<void> _handleProcessedReplay(
    LineOAuthCallbackGuardRecord record,
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

    authController.setErrorMessage(null);
    if (!mounted) {
      return;
    }
    await _finishWithReplayNotice(
      l10n.t('auth_line_callback_already_processed'),
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
    stripLineCallbackCodeFromBrowserUrl(widget.uri);

    if (!mounted) {
      return;
    }

    final destination = savedContext == null
        ? const _LineCallbackFallbackPage()
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
                  l10n.t('auth_line_callback_slow_loading'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FilledButton(
                  key: const Key('line_callback_refresh_button'),
                  onPressed: reloadLineOAuthBrowserPage,
                  child: Text(l10n.t('auth_line_callback_refresh')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LineCallbackFallbackPage extends StatelessWidget {
  const _LineCallbackFallbackPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T-Rider')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Text(
            context.l10n.t('auth_line_callback_error'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
