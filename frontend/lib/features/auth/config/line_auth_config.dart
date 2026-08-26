import 'dart:convert';
import 'dart:math';

class LineAuthConfig {
  static const String _loginChannelId = String.fromEnvironment(
    'LINE_LOGIN_CHANNEL_ID',
    defaultValue: '',
  );

  static const String authorizationEndpoint =
      'https://access.line.me/oauth2/v2.1/authorize';

  static String get loginChannelId => _loginChannelId.trim();

  static bool get isConfigured => loginChannelId.isNotEmpty;

  static String buildRedirectUri({Uri? base}) {
    final resolved = base ?? Uri.base;
    if (resolved.scheme == 'http' || resolved.scheme == 'https') {
      return '${resolved.origin}/auth/line/callback';
    }
    return 'http://localhost/auth/line/callback';
  }

  static String generateOAuthState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Uri buildAuthorizationUri({
    required String redirectUri,
    required String state,
  }) {
    return Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': loginChannelId,
        'redirect_uri': redirectUri,
        'state': state,
        'scope': 'openid profile email',
        'bot_prompt': 'aggressive',
      },
    );
  }
}
