import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
    String? bearerToken,
    Map<String, String>? queryParameters,
  }) async {
    return _request(
      () => _httpClient.get(
        _endpoint(path).replace(queryParameters: queryParameters),
        headers: _headers(bearerToken),
      ),
    );
  }

  Future<List<int>> getBytes(String path, {String? bearerToken}) async {
    try {
      final response = await _httpClient
          .get(_assetEndpoint(path), headers: _headers(bearerToken))
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      _decodeResponse(response);
      throw const ApiException(ApiFailureKind.unknown);
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

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
    required String bearerToken,
  }) async {
    return _request(
      () => _httpClient.patch(
        _endpoint(path),
        headers: _headers(bearerToken),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    required String bearerToken,
  }) async {
    return _request(
      () => _httpClient.delete(
        _endpoint(path),
        headers: _headers(bearerToken),
      ),
    );
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? bearerToken,
    Map<String, String> fields = const {},
    List<ApiMultipartFile> files = const [],
  }) async {
    try {
      final request = http.MultipartRequest('POST', _endpoint(path))
        ..headers['Accept'] = 'application/json'
        ..fields.addAll(fields);
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $bearerToken';
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
      return _decodeResponse(response);
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
    try {
      return _config.endpoint(path);
    } on StateError {
      throw const ApiException(ApiFailureKind.configuration);
    }
  }

  Uri _assetEndpoint(String path) {
    final supplied = Uri.tryParse(path);
    if (supplied != null && supplied.hasScheme && supplied.host.isNotEmpty) {
      return supplied;
    }
    return _endpoint(path);
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
      return _decodeResponse(response);
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

  String absoluteUrl(String path) => _endpoint(path).toString();

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final errorCode = decoded['error_code'] as String?;
    final errors = _errorDetails(decoded['errors']);
    final urgentKind = switch (errorCode) {
      'URGENT_ALREADY_LOCKED' => ApiFailureKind.urgentAlreadyLocked,
      'URGENT_NOT_URGENT_BOOKING' => ApiFailureKind.urgentNotUrgentBooking,
      'URGENT_NEGOTIATION_NOT_BROADCASTING' =>
        ApiFailureKind.urgentNotBroadcasting,
      'URGENT_ETA_INVALID' => ApiFailureKind.urgentEtaInvalid,
      'URGENT_ETA_EXCEEDS_PICKUP_WINDOW' =>
        ApiFailureKind.urgentEtaExceedsPickupWindow,
      'URGENT_NOT_LOCKED_DRIVER' => ApiFailureKind.urgentNotLockedDriver,
      'URGENT_NEGOTIATION_NOT_FOUND' =>
        ApiFailureKind.urgentNegotiationNotFound,
      'URGENT_NOT_LOCKED' => ApiFailureKind.urgentNotLocked,
      'URGENT_ETA_WINDOW_EXPIRED' => ApiFailureKind.urgentEtaExpired,
      'URGENT_ETA_NOT_FAST_ENOUGH' => ApiFailureKind.urgentEtaNotFastEnough,
      _ => null,
    };
    if (urgentKind != null) {
      throw ApiException(
        urgentKind,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    final accountKind = switch (errorCode) {
      'VALIDATION_ERROR' => ApiFailureKind.validation,
      'INVALID_FILE_TYPE' => ApiFailureKind.invalidFileType,
      'FILE_TOO_LARGE' => ApiFailureKind.fileTooLarge,
      'SETTLEMENT_NOT_FOUND' => ApiFailureKind.settlementNotFound,
      'RECEIPT_ALREADY_APPROVED' => ApiFailureKind.receiptAlreadyApproved,
      'VEHICLE_PLATE_ALREADY_REGISTERED' =>
        ApiFailureKind.vehiclePlateAlreadyRegistered,
      _ => null,
    };
    if (accountKind != null) {
      throw ApiException(
        accountKind,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    if (response.statusCode == 401) {
      throw ApiException(
        ApiFailureKind.unauthorized,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    if (response.statusCode == 403) {
      throw ApiException(
        ApiFailureKind.forbidden,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    if (response.statusCode == 404) {
      throw ApiException(
        ApiFailureKind.notFound,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    if (response.statusCode == 409) {
      final kind = switch (errorCode) {
        'DRIVER_STANDBY_TOO_EARLY' => ApiFailureKind.standbyTooEarly,
        'DRIVER_STANDBY_REFERENCE_TIME_MISSING' =>
          ApiFailureKind.standbyReferenceTimeMissing,
        'DRIVER_BOOKING_TIME_CONFLICT' => ApiFailureKind.bookingTimeConflict,
        'ALREADY_ASSIGNED' => ApiFailureKind.alreadyClaimed,
        'INVALID_STATUS_TRANSITION' => ApiFailureKind.invalidStatusTransition,
        'BOOKING_RELEASE_NOT_ALLOWED' => ApiFailureKind.releaseNotAllowed,
        'ASSIGNMENT_ALREADY_RELEASED' =>
          ApiFailureKind.assignmentAlreadyReleased,
        'BOOKING_NOT_ASSIGNED_TO_DRIVER' => ApiFailureKind.bookingNotAssigned,
        'DRIVER_NOT_ELIGIBLE' => ApiFailureKind.driverNotEligible,
        'RECEIPT_ALREADY_APPROVED' => ApiFailureKind.receiptAlreadyApproved,
        _ => ApiFailureKind.conflict,
      };
      throw ApiException(
        kind,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        ApiFailureKind.server,
        statusCode: response.statusCode,
        errorCode: errorCode,
        errors: errors,
      );
    }
    throw ApiException(
      ApiFailureKind.unknown,
      statusCode: response.statusCode,
      errorCode: errorCode,
      errors: errors,
    );
  }

  List<Map<String, dynamic>> _errorDetails(Object? value) {
    if (value is! List) return const [];
    return List.unmodifiable(
      value.whereType<Map>().map(Map<String, dynamic>.from),
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
