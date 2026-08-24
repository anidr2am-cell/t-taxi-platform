import '../../../config/app_config.dart';

class KakaoAuthConfig {
  static const String _restApiKey = String.fromEnvironment(
    'KAKAO_REST_API_KEY',
    defaultValue: '',
  );

  static const String authorizationEndpoint =
      'https://kauth.kakao.com/oauth/authorize';

  static String get restApiKey => _restApiKey.trim();

  static bool get isConfigured => restApiKey.isNotEmpty;

  static String buildRedirectUri({Uri? base}) {
    final resolved = base ?? Uri.base;
    if (resolved.scheme == 'http' || resolved.scheme == 'https') {
      return '${resolved.origin}/auth/kakao/callback';
    }
    return 'http://localhost/auth/kakao/callback';
  }

  static Uri buildAuthorizationUri(String redirectUri) {
    return Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'client_id': restApiKey,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'talk_message',
      },
    );
  }
}
