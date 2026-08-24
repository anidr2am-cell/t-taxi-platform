import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../models/auth_session.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.errorCode, this.statusCode});

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthApiService {
  AuthApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<AuthSession> loginWithGoogleIdToken(String idToken) async {
    final response = await _client.post(
      Uri.parse('$_base/auth/social/google'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'idToken': idToken}),
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Google sign-in failed'
          : 'Google sign-in failed';
      final code = decoded is Map
          ? decoded['error_code'] as String? ?? decoded['code'] as String?
          : null;
      throw AuthApiException(
        message,
        errorCode: code,
        statusCode: response.statusCode,
      );
    }

    final data = Map<String, dynamic>.from((decoded as Map)['data'] as Map);
    return AuthSession.fromJson(data);
  }

  Future<AuthSession> loginWithKakaoCode({
    required String code,
    required String redirectUri,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/auth/social/kakao'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'code': code,
        'redirectUri': redirectUri,
      }),
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Kakao sign-in failed'
          : 'Kakao sign-in failed';
      final code = decoded is Map
          ? decoded['error_code'] as String? ?? decoded['code'] as String?
          : null;
      throw AuthApiException(
        message,
        errorCode: code,
        statusCode: response.statusCode,
      );
    }

    final data = Map<String, dynamic>.from((decoded as Map)['data'] as Map);
    return AuthSession.fromJson(data);
  }
}
