import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../driver/services/driver_session.dart';
import '../models/driver_location.dart';

class DriverLocationApiException implements Exception {
  const DriverLocationApiException(
    this.message, {
    this.errorCode,
    this.statusCode,
  });

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;
}

class DriverLocationApiService {
  DriverLocationApiService({
    http.Client? client,
    String? baseUrl,
    DriverSession? session,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _session = session ?? DriverSession();

  final http.Client _client;
  final String _baseUrl;
  final DriverSession _session;

  static const _adminTokenKey = 'admin_access_token';

  String get _base => '$_baseUrl/api/v1';

  Future<dynamic> _decode(http.Response response) async {
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final map = decoded is Map ? decoded : const {};
      throw DriverLocationApiException(
        map['message'] as String? ?? 'Location request failed',
        errorCode: map['error_code'] as String?,
        statusCode: response.statusCode,
      );
    }
    return decoded is Map ? decoded['data'] : decoded;
  }

  Future<void> updateDriverLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? heading,
    double? speedKph,
    DateTime? recordedAt,
  }) async {
    final token = await _session.tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const DriverLocationApiException('Please log in again');
    }
    try {
      await _session.apiClient.postJson(
        '/driver/location',
        bearerToken: token,
        body: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracyMeters': accuracyMeters,
          'heading': heading,
          'speedKph': speedKph,
          'recordedAt': (recordedAt ?? DateTime.now()).toIso8601String(),
        },
      );
    } on ApiException catch (err) {
      throw await _mapApiException(err);
    }
  }

  Future<List<DriverLocation>> listAdminLocations({
    bool onlineOnly = false,
    bool activeJobOnly = false,
    bool staleOnly = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_adminTokenKey);
    if (token == null || token.isEmpty) {
      throw const DriverLocationApiException('Please log in');
    }
    final uri = Uri.parse('$_base/admin/drivers/locations').replace(
      queryParameters: {
        if (onlineOnly) 'onlineOnly': 'true',
        if (activeJobOnly) 'activeJobOnly': 'true',
        if (staleOnly) 'staleOnly': 'true',
      },
    );
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    final data = Map<String, dynamic>.from(await _decode(response) as Map);
    final items = data['items'] as List? ?? const [];
    return items
        .map((item) => DriverLocation.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<GuestDriverLocationResult> getGuestDriverLocation({
    required int bookingId,
    String guestAccessToken = '',
    String? customerAccessToken,
    bool useCustomerAuth = false,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    final guestToken = guestAccessToken.trim();
    final customerToken = customerAccessToken?.trim() ?? '';

    if (useCustomerAuth && guestToken.isEmpty && customerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerToken';
    } else if (guestToken.isNotEmpty) {
      headers['X-Guest-Access-Token'] = guestToken;
    } else if (customerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerToken';
    } else {
      throw const DriverLocationApiException(
        'Booking is not accessible',
        errorCode: 'BOOKING_NOT_ACCESSIBLE',
      );
    }

    final response = await _client.get(
      Uri.parse('$_base/public/bookings/$bookingId/driver-location'),
      headers: headers,
    );
    return GuestDriverLocationResult.fromJson(
      Map<String, dynamic>.from(await _decode(response) as Map),
    );
  }

  Future<DriverLocationApiException> _mapApiException(ApiException err) async {
    if (err.kind == ApiFailureKind.unauthorized) {
      await _session.expireSession();
    }
    return DriverLocationApiException(
      err.message ?? 'Location request failed',
      errorCode: err.errorCode,
      statusCode: err.statusCode,
    );
  }
}
