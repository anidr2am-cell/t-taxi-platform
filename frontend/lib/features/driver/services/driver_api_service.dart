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
  const DriverApiService();

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

  Future<void> login({required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
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
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        await logout();
      }
      throw DriverApiException(
        decoded['message'] as String? ?? 'Request failed',
      );
    }

    return decoded['data'];
  }

  Future<dynamic> _post(String path, {Map<String, dynamic>? body}) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const DriverApiException('Please log in again');
    }

    final response = await http.post(
      Uri.parse('$_base$path'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body ?? {}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        await logout();
      }
      throw DriverApiException(
        decoded['message'] as String? ?? 'Request failed',
      );
    }

    return decoded['data'];
  }

  Future<Map<String, dynamic>> getRatingSummary() async {
    final data = await _get('/driver/rating-summary');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<DriverJobsToday> getTodayBookings() async {
    final data = await _get('/driver/bookings/today');
    return DriverJobsToday.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    final data = await _get('/driver/bookings/$bookingNumber');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> markArrived(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/arrive');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> scanBoarding(String bookingNumber, String token) async {
    final data = await _post(
      '/driver/bookings/$bookingNumber/scan-boarding',
      body: {'token': token},
    );
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> scanDropoff(String bookingNumber, String token) async {
    final data = await _post(
      '/driver/bookings/$bookingNumber/scan-dropoff',
      body: {'token': token},
    );
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async {
    final query = unreadOnly == true ? '?unreadOnly=true' : '';
    final data = await _get('/driver/notifications$query');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<int> getUnreadNotificationCount() async {
    final data = await _get('/driver/notifications/unread-count');
    return Map<String, dynamic>.from(data as Map)['unreadCount'] as int? ?? 0;
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _post('/driver/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _post('/driver/notifications/read-all');
  }
}
