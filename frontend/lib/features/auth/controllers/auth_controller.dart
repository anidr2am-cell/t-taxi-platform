import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:google_sign_in/google_sign_in.dart';

import '../config/kakao_auth_config.dart';
import '../config/line_auth_config.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/social_login_return_context.dart';
import '../services/auth_api_service.dart';
import '../services/auth_token_storage.dart';
import '../services/google_sign_in_service.dart';
import '../services/kakao_oauth_service.dart';
import '../services/line_oauth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    AuthApiService? apiService,
    AuthTokenStorage? tokenStorage,
    GoogleSignInService? googleSignInService,
    KakaoOAuthService? kakaoOAuthService,
    LineOAuthService? lineOAuthService,
    SocialLoginReturnStorage? returnStorage,
  }) : _apiService = apiService ?? AuthApiService(),
       _tokenStorage = tokenStorage ?? AuthTokenStorage(),
       _googleSignInService = googleSignInService ?? GoogleSignInService(),
       _kakaoOAuthService = kakaoOAuthService ?? KakaoOAuthService(),
       _lineOAuthService = lineOAuthService ?? LineOAuthService(),
       _returnStorage = returnStorage ?? SocialLoginReturnStorage() {
    unawaited(initialize());
  }

  final AuthApiService _apiService;
  final AuthTokenStorage _tokenStorage;
  final GoogleSignInService _googleSignInService;
  final KakaoOAuthService _kakaoOAuthService;
  final LineOAuthService _lineOAuthService;
  final SocialLoginReturnStorage _returnStorage;

  AuthSession? _session;
  bool _isLoading = false;
  bool _initialized = false;
  bool _hadPersistedSessionAtInit = false;
  String? _errorMessage;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;
  SocialLoginReturnContext? _pendingClaimContext;

  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _session != null;
  bool get hadPersistedSessionAtInit => _hadPersistedSessionAtInit;
  AuthUser? get user => _session?.user;
  String? get errorMessage => _errorMessage;
  bool get isKakaoSignInAvailable => KakaoAuthConfig.isConfigured;
  bool get isLineSignInAvailable => LineAuthConfig.isConfigured;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _session = await _tokenStorage.loadSession();
    _hadPersistedSessionAtInit = _session != null;

    if (kIsWeb) {
      await _googleSignInService.ensureInitialized();
      _attachGoogleAuthenticationListener();
    }

    _initialized = true;
    notifyListeners();
  }

  void setPendingClaimContext(SocialLoginReturnContext? context) {
    _pendingClaimContext = context;
  }

  void clearPendingClaimContext() {
    _pendingClaimContext = null;
  }

  @visibleForTesting
  SocialLoginReturnContext? get pendingClaimContextForTest => _pendingClaimContext;

  @visibleForTesting
  void attachGoogleAuthenticationListenerForTest() {
    _attachGoogleAuthenticationListener();
  }

  void _attachGoogleAuthenticationListener() {
    _googleAuthSubscription ??= _googleSignInService.authenticationEvents
        .listen(_handleGoogleAuthenticationEvent);
  }

  SocialLoginReturnContext? _resolveClaimContext(
    SocialLoginReturnContext? explicit,
  ) {
    return explicit ?? _pendingClaimContext;
  }

  Future<void> signInWithGoogle({SocialLoginReturnContext? claimContext}) async {
    _errorMessage = null;
    final idToken = await _googleSignInService.authenticateAndGetIdToken();
    if (idToken == null || idToken.isEmpty) {
      return;
    }
    await _completeSignInWithIdToken(
      idToken,
      claimContext: _resolveClaimContext(claimContext),
    );
  }

  Future<void> beginKakaoSignIn(SocialLoginReturnContext returnContext) async {
    if (!KakaoAuthConfig.isConfigured) {
      _errorMessage = 'Kakao sign-in is not configured';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    notifyListeners();

    await _returnStorage.save(returnContext);
    await _kakaoOAuthService.startAuthorization(returnContext.redirectUri);
  }

  Future<void> beginLineSignIn(SocialLoginReturnContext returnContext) async {
    if (!LineAuthConfig.isConfigured) {
      _errorMessage = 'LINE sign-in is not configured';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    notifyListeners();

    await _returnStorage.save(returnContext);
    await _lineOAuthService.startAuthorization(returnContext.redirectUri);
  }

  Future<void> completeSignInWithKakaoCode({
    required String code,
    required String redirectUri,
    SocialLoginReturnContext? claimContext,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await _apiService.loginWithKakaoCode(
        code: code,
        redirectUri: redirectUri,
      );
      await _tokenStorage.saveSession(session);
      _session = session;
      await _maybeClaimGuestBooking(claimContext);
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> completeSignInWithLineCode({
    required String code,
    required String redirectUri,
    SocialLoginReturnContext? claimContext,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await _apiService.loginWithLineCode(
        code: code,
        redirectUri: redirectUri,
      );
      await _tokenStorage.saveSession(session);
      _session = session;
      await _maybeClaimGuestBooking(claimContext);
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<void> completeSignInWithIdTokenForTest(
    String idToken, {
    SocialLoginReturnContext? claimContext,
  }) {
    return _completeSignInWithIdToken(idToken, claimContext: claimContext);
  }

  @visibleForTesting
  Future<void> completeSignInWithKakaoCodeForTest({
    required String code,
    required String redirectUri,
    SocialLoginReturnContext? claimContext,
  }) {
    return completeSignInWithKakaoCode(
      code: code,
      redirectUri: redirectUri,
      claimContext: claimContext,
    );
  }

  @visibleForTesting
  Future<void> completeSignInWithLineCodeForTest({
    required String code,
    required String redirectUri,
    SocialLoginReturnContext? claimContext,
  }) {
    return completeSignInWithLineCode(
      code: code,
      redirectUri: redirectUri,
      claimContext: claimContext,
    );
  }

  @visibleForTesting
  void setErrorMessage(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> _completeSignInWithIdToken(
    String idToken, {
    SocialLoginReturnContext? claimContext,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await _apiService.loginWithGoogleIdToken(idToken);
      await _tokenStorage.saveSession(session);
      _session = session;
      await _maybeClaimGuestBooking(_resolveClaimContext(claimContext));
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _maybeClaimGuestBooking(SocialLoginReturnContext? context) async {
    if (context == null) {
      return;
    }

    final bookingNumber = context.result.bookingNumber.trim();
    final guestToken = context.result.guestAccessToken?.trim();
    if (bookingNumber.isEmpty || guestToken == null || guestToken.isEmpty) {
      return;
    }

    final accessToken = _session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    try {
      await _apiService.claimBooking(
        accessToken: accessToken,
        bookingNumber: bookingNumber,
        guestAccessToken: guestToken,
      );
    } catch (_) {
      // Claim failure must not affect a successful sign-in experience.
    }
  }

  void _handleGoogleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    if (event is! GoogleSignInAuthenticationEventSignIn) {
      return;
    }
    final idToken = event.user.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      return;
    }
    unawaited(
      _completeSignInWithIdToken(
        idToken,
        claimContext: _resolveClaimContext(null),
      ),
    );
  }

  Future<void> signOut() async {
    await _tokenStorage.clear();
    _session = null;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_googleAuthSubscription?.cancel());
    super.dispose();
  }
}
