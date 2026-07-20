import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({
    required AppConfig config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _config = config,
       _httpClient = httpClient ?? http.Client();

  final AppConfig _config;
  final http.Client _httpClient;
  final Duration timeout;

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    return _request(
      () => _httpClient.post(
        _endpoint(path),
        headers: _headers(bearerToken),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    required String bearerToken,
  }) async {
    return _request(
      () => _httpClient.get(_endpoint(path), headers: _headers(bearerToken)),
    );
  }

  Uri _endpoint(String path) {
    try {
      return _config.endpoint(path);
    } on StateError {
      throw const ApiException(ApiFailureKind.configuration);
    }
  }

  Map<String, String> _headers(String? bearerToken) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
  };

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    try {
      final response = await send().timeout(timeout);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException(ApiFailureKind.invalidResponse);
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      final errorCode = decoded['error_code'] as String?;
      if (response.statusCode == 401) {
        throw ApiException(
          ApiFailureKind.unauthorized,
          statusCode: response.statusCode,
          errorCode: errorCode,
        );
      }
      if (response.statusCode == 403) {
        throw ApiException(
          ApiFailureKind.forbidden,
          statusCode: response.statusCode,
          errorCode: errorCode,
        );
      }
      if (response.statusCode == 404) {
        throw ApiException(
          ApiFailureKind.notFound,
          statusCode: response.statusCode,
          errorCode: errorCode,
        );
      }
      if (response.statusCode == 409) {
        throw ApiException(
          ApiFailureKind.conflict,
          statusCode: response.statusCode,
          errorCode: errorCode,
        );
      }
      if (response.statusCode >= 500) {
        throw ApiException(
          ApiFailureKind.server,
          statusCode: response.statusCode,
          errorCode: errorCode,
        );
      }
      throw ApiException(
        ApiFailureKind.unknown,
        statusCode: response.statusCode,
        errorCode: errorCode,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(ApiFailureKind.timeout);
    } on http.ClientException {
      throw const ApiException(ApiFailureKind.unavailable);
    } on FormatException {
      throw const ApiException(ApiFailureKind.invalidResponse);
    } catch (_) {
      throw const ApiException(ApiFailureKind.unknown);
    }
  }
}
