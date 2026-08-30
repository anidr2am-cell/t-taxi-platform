import 'api_client.dart';
import 'api_exception.dart';
import 'token_storage.dart';

/// Refreshes access tokens using the stored refresh token.
///
/// Concurrent callers share a single in-flight refresh request.
class AuthTokenRefresher {
  AuthTokenRefresher({
    required TokenStorage storage,
    required ApiClient client,
  }) : _storage = storage,
       _client = client;

  final TokenStorage _storage;
  final ApiClient _client;
  Future<String?>? _inFlightRefresh;

  Future<String?> refreshAccessToken() {
    return _inFlightRefresh ??= _refresh().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<String?> _refresh() async {
    final tokens = await _storage.read();
    final refreshToken = tokens?.refreshToken?.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    try {
      final response = await _client.postJson(
        '/api/v1/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      final data = response['data'];
      if (response['success'] != true || data is! Map<String, dynamic>) {
        return null;
      }
      final accessToken = data['accessToken'];
      final expiresIn = data['expiresIn'];
      if (accessToken is! String || accessToken.isEmpty) {
        return null;
      }

      final expiresAt = expiresIn is num
          ? DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt()))
          : tokens?.accessTokenExpiresAt;

      await _storage.write(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          accessTokenExpiresAt: expiresAt,
        ),
      );
      return accessToken;
    } on ApiException {
      return null;
    }
  }
}
