import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  GoogleSignInService({this.clientId});

  final String? clientId;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await GoogleSignIn.instance.initialize(clientId: clientId);
    _initialized = true;
  }

  bool get supportsInteractiveSignIn =>
      GoogleSignIn.instance.supportsAuthenticate();

  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      GoogleSignIn.instance.authenticationEvents;

  Future<String?> authenticateAndGetIdToken() async {
    await ensureInitialized();
    if (!supportsInteractiveSignIn) {
      return null;
    }
    final account = await GoogleSignIn.instance.authenticate();
    return account.authentication.idToken;
  }

  @visibleForTesting
  void markInitializedForTest() {
    _initialized = true;
  }
}
