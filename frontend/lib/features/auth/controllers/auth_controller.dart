import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:google_sign_in/google_sign_in.dart';

import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../services/auth_api_service.dart';
import '../services/auth_token_storage.dart';
import '../services/google_sign_in_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    AuthApiService? apiService,
    AuthTokenStorage? tokenStorage,
    GoogleSignInService? googleSignInService,
  }) : _apiService = apiService ?? AuthApiService(),
       _tokenStorage = tokenStorage ?? AuthTokenStorage(),
       _googleSignInService = googleSignInService ?? GoogleSignInService() {
    unawaited(initialize());
  }

  final AuthApiService _apiService;
  final AuthTokenStorage _tokenStorage;
  final GoogleSignInService _googleSignInService;

  AuthSession? _session;
  bool _isLoading = false;
  bool _initialized = false;
  String? _errorMessage;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;

  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _session != null;
  AuthUser? get user => _session?.user;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _session = await _tokenStorage.loadSession();

    if (kIsWeb) {
      await _googleSignInService.ensureInitialized();
      _googleAuthSubscription ??= _googleSignInService.authenticationEvents
          .listen(_handleGoogleAuthenticationEvent);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    _errorMessage = null;
    final idToken = await _googleSignInService.authenticateAndGetIdToken();
    if (idToken == null || idToken.isEmpty) {
      return;
    }
    await _completeSignInWithIdToken(idToken);
  }

  @visibleForTesting
  Future<void> completeSignInWithIdTokenForTest(String idToken) {
    return _completeSignInWithIdToken(idToken);
  }

  Future<void> _completeSignInWithIdToken(String idToken) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await _apiService.loginWithGoogleIdToken(idToken);
      await _tokenStorage.saveSession(session);
      _session = session;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
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
    unawaited(_completeSignInWithIdToken(idToken));
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
