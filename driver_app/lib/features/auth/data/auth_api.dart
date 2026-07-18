import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';
import 'auth_models.dart';

abstract interface class AuthDataSource {
  Future<AuthSession> login(String loginId, String password);
  Future<DriverUser> getMe(String accessToken);
  Future<void> logout(AuthTokens tokens);
}

class AuthApi implements AuthDataSource {
  const AuthApi(this._client);

  final ApiClient _client;

  @override
  Future<AuthSession> login(String loginId, String password) async {
    try {
      final response = await _client.postJson(
        '/api/v1/auth/login',
        body: buildLoginRequest(loginId: loginId, password: password),
      );
      return AuthSession.fromEnvelope(response);
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized ||
          (error.statusCode != null && error.statusCode! < 500)) {
        throw ApiException(
          ApiFailureKind.invalidCredentials,
          statusCode: error.statusCode,
          errorCode: error.errorCode,
        );
      }
      rethrow;
    }
  }

  @override
  Future<DriverUser> getMe(String accessToken) async {
    final response = await _client.getJson(
      '/api/v1/auth/me',
      bearerToken: accessToken,
    );
    final data = response['data'];
    if (response['success'] != true || data is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return DriverUser.fromJson(data);
  }

  @override
  Future<void> logout(AuthTokens tokens) async {
    await _client.postJson(
      '/api/v1/auth/logout',
      bearerToken: tokens.accessToken,
      body: {'refreshToken': ?tokens.refreshToken},
    );
  }
}
