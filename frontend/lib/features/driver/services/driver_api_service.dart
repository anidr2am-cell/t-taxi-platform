import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/driver_booking.dart';

class DriverApiException implements Exception {
  const DriverApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriverApiService {
  static const _tokenKey = 'driver_access_token';

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw DriverApiException(decoded['message'] as String? ?? 'Login failed');
    }

    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);
    if (user['role'] != 'DRIVER') {
      throw const DriverApiException('Driver account required');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['accessToken'] as String);
  }

  Future<dynamic> _get(String path) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const DriverApiException('Please log in again');
    }

    final response = await http.get(
      Uri.parse('$_base$path'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        await logout();
      }
      throw DriverApiException(decoded['message'] as String? ?? 'Request failed');
    }

    return decoded['data'];
  }

  Future<DriverJobsToday> getTodayBookings() async {
    final data = await _get('/driver/bookings/today');
    return DriverJobsToday.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    final data = await _get('/driver/bookings/$bookingNumber');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
