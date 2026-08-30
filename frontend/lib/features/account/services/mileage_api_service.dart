import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../auth/services/auth_token_storage.dart';

class MileageApiException implements Exception {
  const MileageApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MileageBalanceResult {
  const MileageBalanceResult({required this.balance});

  final int balance;
}

class MileageApiService {
  MileageApiService({
    http.Client? client,
    AuthTokenStorage? tokenStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? AuthTokenStorage(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final AuthTokenStorage _tokenStorage;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<MileageBalanceResult> getMileageBalance() async {
    final session = await _tokenStorage.loadSession();
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const MileageApiException('Authentication required');
    }

    final response = await _client.get(
      Uri.parse('$_base/customer/mileage'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Unable to load mileage balance'
          : 'Unable to load mileage balance';
      throw MileageApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    final data = Map<String, dynamic>.from((decoded as Map)['data'] as Map);
    return MileageBalanceResult(
      balance: (data['balance'] as num?)?.toInt() ?? 0,
    );
  }
}
