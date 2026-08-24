import '../config/kakao_auth_config.dart';
import 'kakao_oauth_launcher.dart';

class KakaoOAuthService {
  KakaoOAuthService({KakaoOAuthLauncher? launcher})
    : _launcher = launcher ?? const KakaoOAuthLauncher();

  final KakaoOAuthLauncher _launcher;

  Future<void> startAuthorization(String redirectUri) async {
    if (!KakaoAuthConfig.isConfigured) {
      throw StateError('Kakao sign-in is not configured');
    }
    final authorizationUri = KakaoAuthConfig.buildAuthorizationUri(redirectUri);
    await _launcher.redirectToAuthorization(authorizationUri);
  }
}
