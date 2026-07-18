import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';

class DriverUser {
  const DriverUser({
    required this.id,
    required this.role,
    required this.isActive,
    this.name,
    this.phone,
    this.email,
  });

  factory DriverUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final role = json['role'];
    final isActive = json['isActive'];
    if (id is! num || role is! String || isActive is! bool) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return DriverUser(
      id: id.toInt(),
      role: role,
      isActive: isActive,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }

  final int id;
  final String role;
  final bool isActive;
  final String? name;
  final String? phone;
  final String? email;
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
  });

  factory AuthSession.fromEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (envelope['success'] != true || data is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final accessToken = data['accessToken'];
    final user = data['user'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        user is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final refreshToken = data['refreshToken'];
    final expiresIn = data['expiresIn'];
    if (refreshToken != null && refreshToken is! String) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return AuthSession(
      user: DriverUser.fromJson(user),
      accessToken: accessToken,
      refreshToken: refreshToken as String?,
      expiresIn: expiresIn is num ? expiresIn.toInt() : null,
    );
  }

  final DriverUser user;
  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;

  AuthTokens get tokens =>
      AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
}

Map<String, dynamic> buildLoginRequest({
  required String loginId,
  required String password,
}) {
  final normalized = loginId.trim();
  return {
    if (normalized.contains('@')) 'email': normalized else 'phone': normalized,
    'password': password,
  };
}
