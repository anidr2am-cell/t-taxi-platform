import 'auth_user.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;
  final int? expiresIn;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: AuthUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      expiresIn: json['expiresIn'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'user': user.toJson(),
    if (expiresIn != null) 'expiresIn': expiresIn,
  };
}
