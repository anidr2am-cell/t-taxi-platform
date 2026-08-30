/// Persisted auth tokens for injectable refresh clients.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;
}

abstract interface class TokenStorage {
  Future<AuthTokens?> read();

  Future<void> write(AuthTokens tokens);

  Future<void> clear();
}
