import 'package:flutter/foundation.dart';

import '../config/line_auth_config.dart';
import '../models/line_oauth_state_storage.dart';
import 'line_oauth_launcher.dart';
import 'line_oauth_state_storage.dart';

class LineOAuthService {
  LineOAuthService({
    LineOAuthLauncher? launcher,
    LineOAuthStateStorage? stateStorage,
  })  : _launcher = launcher ?? const LineOAuthLauncher(),
        _stateStorage = stateStorage ?? createLineOAuthStateStorage();

  final LineOAuthLauncher _launcher;
  final LineOAuthStateStorage _stateStorage;

  Future<void> startAuthorization(String redirectUri) async {
    if (!LineAuthConfig.isConfigured) {
      throw StateError('LINE sign-in is not configured');
    }

    final state = LineAuthConfig.generateOAuthState();
    await _stateStorage.save(state);
    final authorizationUri = LineAuthConfig.buildAuthorizationUri(
      redirectUri: redirectUri,
      state: state,
    );
    await _launcher.redirectToAuthorization(authorizationUri);
  }

  @visibleForTesting
  LineOAuthStateStorage get stateStorage => _stateStorage;
}
