import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_exception.dart';
import 'auth_token_refresher.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    AuthTokenRefresher? tokenRefresher,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _httpClient = httpClient ?? http.Client(),
       _tokenRefresher = tokenRefresher;

  final String _baseUrl;
  final http.Client _httpClient;
  final Duration timeout;
  final AuthTokenRefresher? _tokenRefresher;

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    return _request(
      path: path,
      bearerToken: bearerToken,
      send: (token) => _httpClient.post(
        _endpoint(path),
        headers: _headers(token),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? bearerToken,
    Map<String, String>? queryParameters,
  }) async {
    return _request(
      path: path,
      bearerToken: bearerToken,
      send: (token) => _httpClient.get(
        _endpoint(path).replace(queryParameters: queryParameters),
        headers: _headers(token),
      ),
    );
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
    required String bearerToken,
  }) async {
    return _request(
      path: path,
      bearerToken: bearerToken,
      send: (token) => _httpClient.patch(
        _endpoint(path),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    required String bearerToken,
  }) async {
    return _request(
      path: path,
      bearerToken: bearerToken,
      send: (token) => _httpClient.delete(
        _endpoint(path),
        headers: _headers(token),
      ),
    );
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? bearerToken,
    Map<String, String> fields = const {},
    List<ApiMultipartFile> files = const [],
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    try {
      return await _requestMultipart(
        path: path,
        bearerToken: bearerToken,
        fields: fields,
        files: files,
        headers: headers,
        timeout: timeout ?? this.timeout,
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

  Uri _endpoint(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    if (normalized.startsWith('/api/v1/') || normalized == '/api/v1') {
      return Uri.parse('$_baseUrl$normalized');
    }
    return Uri.parse('$_baseUrl/api/v1$normalized');
  }

  Map<String, String> _headers(String? bearerToken) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (bearerToken != null && bearerToken.isNotEmpty)
      'Authorization': 'Bearer $bearerToken',
  };

  Future<Map<String, dynamic>> _request({
    required String path,
    required Future<http.Response> Function(String? bearerToken) send,
    String? bearerToken,
  }) async {
    try {
      var token = bearerToken;
      for (var attempt = 0; attempt < 2; attempt++) {
        final response = await send(token).timeout(timeout);
        if (response.statusCode == 401 &&
            attempt == 0 &&
            token != null &&
            token.isNotEmpty &&
            _shouldAttemptTokenRefresh(path)) {
          final refreshed = await _tokenRefresher?.refreshAccessToken();
          if (refreshed != null && refreshed.isNotEmpty) {
            token = refreshed;
            continue;
          }
        }
        return _decodeResponse(response);
      }
      throw const ApiException(ApiFailureKind.unauthorized, statusCode: 401);
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

  Future<Map<String, dynamic>> _requestMultipart({
    required String path,
    String? bearerToken,
    Map<String, String> fields = const {},
    List<ApiMultipartFile> files = const [],
    Map<String, String> headers = const {},
    required Duration timeout,
  }) async {
    var token = bearerToken;
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.MultipartRequest('POST', _endpoint(path))
        ..headers['Accept'] = 'application/json'
        ..headers.addAll(headers)
        ..fields.addAll(fields);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      for (final file in files) {
        request.files.add(
          http.MultipartFile.fromBytes(
            file.field,
            file.bytes,
            filename: file.filename,
            contentType: file.contentType == null
                ? null
                : MediaType.parse(file.contentType!),
          ),
        );
      }
      final streamed = await _httpClient.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401 &&
          attempt == 0 &&
          token != null &&
          token.isNotEmpty &&
          _shouldAttemptTokenRefresh(path)) {
        final refreshed = await _tokenRefresher?.refreshAccessToken();
        if (refreshed != null && refreshed.isNotEmpty) {
          token = refreshed;
          continue;
        }
      }
      return _decodeResponse(response);
    }
    throw const ApiException(ApiFailureKind.unauthorized, statusCode: 401);
  }

  bool _shouldAttemptTokenRefresh(String path) {
    if (_tokenRefresher == null) return false;
    final normalized = path.split('?').first;
    return normalized != '/api/v1/auth/login' &&
        normalized != '/auth/login' &&
        normalized != '/api/v1/auth/refresh' &&
        normalized != '/auth/refresh' &&
        normalized != '/api/v1/auth/register' &&
        normalized != '/auth/register';
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final errorCode =
        decoded['error_code'] as String? ?? decoded['code'] as String?;
    final message = decoded['message'] as String?;
    final details = decoded['details'] is Map
        ? Map<String, dynamic>.from(decoded['details'] as Map)
        : null;
    if (response.statusCode == 401) {
      throw ApiException(
        ApiFailureKind.unauthorized,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        details: details,
      );
    }
    if (response.statusCode == 403) {
      throw ApiException(
        ApiFailureKind.forbidden,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        details: details,
      );
    }
    if (response.statusCode == 404) {
      throw ApiException(
        ApiFailureKind.notFound,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        details: details,
      );
    }
    if (response.statusCode == 409) {
      throw ApiException(
        ApiFailureKind.conflict,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        details: details,
      );
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        ApiFailureKind.server,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        details: details,
      );
    }
    throw ApiException(
      ApiFailureKind.unknown,
      statusCode: response.statusCode,
      errorCode: errorCode,
      message: message,
      details: details,
    );
  }
}

class ApiMultipartFile {
  const ApiMultipartFile({
    required this.field,
    required this.filename,
    required this.bytes,
    this.contentType,
  });

  final String field;
  final String filename;
  final List<int> bytes;
  final String? contentType;
}
