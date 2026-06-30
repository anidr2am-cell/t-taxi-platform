import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/driver_location.dart';

class DriverLocationApiException implements Exception {
  const DriverLocationApiException(this.message, {this.errorCode, this.statusCode});

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;
}

class DriverLocationApiService {
  DriverLocationApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const _driverTokenKey = 'driver_access_token';
  static const _adminTokenKey = 'admin_access_token';

  String get _base => '$_baseUrl/api/v1';

  Future<String?> _token(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

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
    final token = await _token(_driverTokenKey);
    if (token == null || token.isEmpty) {
      throw const DriverLocationApiException('Please log in again');
    }
    final response = await _client.post(
      Uri.parse('$_base/driver/location'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'heading': heading,
        'speedKph': speedKph,
        'recordedAt': (recordedAt ?? DateTime.now()).toIso8601String(),
      }),
    );
    await _decode(response);
  }

  Future<List<DriverLocation>> listAdminLocations({
    bool onlineOnly = false,
    bool activeJobOnly = false,
    bool staleOnly = false,
  }) async {
    final token = await _token(_adminTokenKey);
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
    required String guestAccessToken,
  }) async {
    final response = await _client.get(
      Uri.parse('$_base/public/bookings/$bookingId/driver-location'),
      headers: {'Accept': 'application/json', 'X-Guest-Access-Token': guestAccessToken},
    );
    return GuestDriverLocationResult.fromJson(
      Map<String, dynamic>.from(await _decode(response) as Map),
    );
  }
}
