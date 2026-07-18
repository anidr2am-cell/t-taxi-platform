import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';
import 'auth_api.dart';
import 'auth_models.dart';

class AuthRepository {
  const AuthRepository({
    required AuthDataSource api,
    required TokenStorage storage,
  }) : _api = api,
       _storage = storage;

  final AuthDataSource _api;
  final TokenStorage _storage;

  Future<AuthSession> login(String loginId, String password) async {
    final session = await _api.login(loginId, password);
    if (session.user.role != 'DRIVER' || !session.user.isActive) {
      throw const ApiException(ApiFailureKind.invalidCredentials);
    }
    await _storage.write(session.tokens);
    return session;
  }

  Future<AuthSession?> restoreSession() async {
    final tokens = await _storage.read();
    if (tokens == null) return null;
    try {
      final user = await _api.getMe(tokens.accessToken);
      if (user.role != 'DRIVER' || !user.isActive) {
        await _storage.clear();
        return null;
      }
      return AuthSession(
        user: user,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await _storage.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final tokens = await _storage.read();
    try {
      if (tokens != null) await _api.logout(tokens);
    } catch (_) {
      // Server logout is best effort. Local credentials must always be removed.
    } finally {
      await _storage.clear();
    }
  }

  Future<void> clearLocalSession() => _storage.clear();
}
