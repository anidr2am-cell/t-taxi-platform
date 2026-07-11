import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';

class DriverApiException implements Exception {
  const DriverApiException(this.message, {this.errorCode, this.statusCode});

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;

  bool get isStaleStatus =>
      errorCode == 'INVALID_STATUS_TRANSITION' ||
      errorCode == 'BOOKING_NOT_FOUND' ||
      message.toLowerCase().contains('invalid status');
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
    final token = prefs.getString(_tokenKey);
    if (token != null && token.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('$_base/auth/logout'),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({}),
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Logout is best effort; local session cleanup must still happen.
      }
    }
    await prefs.remove(_tokenKey);
  }

  Future<void> login({required String email, required String password}) async {
    final loginId = email.trim();
    final isPhone = !loginId.contains('@');
    final response = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        if (isPhone) 'phone': loginId else 'email': loginId,
        'password': password,
      }),
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
        errorCode: decoded['error_code'] as String?,
        statusCode: response.statusCode,
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
        errorCode: decoded['error_code'] as String?,
        statusCode: response.statusCode,
      );
    }

    return decoded['data'];
  }

  Future<Map<String, dynamic>> getRatingSummary() async {
    final data = await _get('/driver/rating-summary');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<DriverStatus> getStatus() async {
    final data = await _get('/driver/status');
    return DriverStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverStatus> goOnline() async {
    final data = await _post('/driver/online');
    return DriverStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverStatus> goOffline() async {
    final data = await _post('/driver/offline');
    return DriverStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverJobsToday> getTodayBookings() async {
    final data = await _get('/driver/bookings/today');
    return DriverJobsToday.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    final data = await _get('/driver/bookings/$bookingNumber');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> startOnRoute(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/start-route');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> markArrived(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/arrive');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> markPickedUp(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/mark-picked-up');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> endTrip(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/end-trip');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> completeTrip(String bookingNumber) async {
    return endTrip(bookingNumber);
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
