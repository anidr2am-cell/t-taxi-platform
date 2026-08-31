import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../models/auth_session.dart';
import 'customer_api_errors.dart';
import 'customer_session.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.errorCode, this.statusCode});

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthApiService {
  AuthApiService({
    http.Client? client,
    String? baseUrl,
    CustomerSession? customerSession,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _customerSession = customerSession ?? CustomerSession();

  final http.Client _client;
  final String _baseUrl;
  final CustomerSession _customerSession;

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

  Future<AuthSession> loginWithLineCode({
    required String code,
    required String redirectUri,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/auth/social/line'),
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
          ? decoded['message'] as String? ?? 'LINE sign-in failed'
          : 'LINE sign-in failed';
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

  Future<void> claimBooking({
    required String bookingNumber,
    required String guestAccessToken,
    String? accessToken,
  }) async {
    final bearerToken =
        accessToken ?? await _customerSession.tokenStorage.readAccessToken();
    if (bearerToken == null || bearerToken.isEmpty) {
      throw const AuthApiException(
        'Authentication required',
        statusCode: 401,
      );
    }

    try {
      await _customerSession.apiClient.postJson(
        '/customer/bookings/claim',
        bearerToken: bearerToken,
        body: {
          'bookingNumber': bookingNumber,
          'guestAccessToken': guestAccessToken,
        },
      );
    } on ApiException catch (error) {
      throw AuthApiException(
        customerApiErrorMessage(error, fallback: 'Unable to link booking'),
        errorCode: error.errorCode,
        statusCode: error.statusCode,
      );
    }
  }
}
