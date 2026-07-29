import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../models/flight_lookup_models.dart';

class FlightLookupException implements Exception {
  FlightLookupException({
    required this.errorCode,
    required this.message,
  });

  final String errorCode;
  final String message;

  @override
  String toString() => 'FlightLookupException($errorCode: $message)';
}

class FlightLookupApiService {
  static final FlightLookupApiService _instance = FlightLookupApiService._();
  factory FlightLookupApiService() => _instance;

  FlightLookupApiService._({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  FlightLookupApiService.test({
    required http.Client client,
    required String baseUrl,
  }) : this._(client: client, baseUrl: baseUrl);

  final http.Client _client;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<FlightSearchResult> searchFlight(
    String flightNumber,
    String flightDate,
  ) async {
    final uri = Uri.parse('$_base/public/flights/search').replace(
      queryParameters: {
        'flightNumber': flightNumber.trim(),
        'flightDate': flightDate.trim(),
      },
    );
    final response = await _client.get(uri);
    final decoded = jsonDecode(response.body);

    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? (decoded['message'] as String? ?? 'Request failed')
          : 'Request failed';
      final errorCode = decoded is Map
          ? (decoded['error_code'] as String? ??
              decoded['code'] as String? ??
              'UNKNOWN')
          : 'UNKNOWN';
      throw FlightLookupException(errorCode: errorCode, message: message);
    }

    if (decoded is! Map || !decoded.containsKey('data')) {
      throw FlightLookupException(
        errorCode: 'UNKNOWN',
        message: 'Malformed flight lookup response',
      );
    }

    return FlightSearchResult.fromJson(
      Map<String, dynamic>.from(decoded['data'] as Map),
    );
  }
}
