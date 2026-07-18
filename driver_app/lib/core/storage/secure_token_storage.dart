import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}

abstract interface class TokenStorage {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'auth_access_token';
  static const refreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final accessToken = await _storage.read(key: accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) return null;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: await _storage.read(key: refreshTokenKey),
    );
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await _storage.write(key: accessTokenKey, value: tokens.accessToken);
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _storage.delete(key: refreshTokenKey);
    } else {
      await _storage.write(key: refreshTokenKey, value: refreshToken);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
  }
}
