import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminDispatchApiException implements Exception {
  const AdminDispatchApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminDispatchApiService {
  const AdminDispatchApiService();

  static const _tokenKey = 'admin_access_token';

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
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw AdminDispatchApiException(decoded['message'] as String? ?? 'Login failed');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);
    final role = user['role'] as String?;
    if (role != 'ADMIN' && role != 'SUPER_ADMIN') {
      throw const AdminDispatchApiException('Admin account required');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['accessToken'] as String);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminDispatchApiException('Please log in');
    }

    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    final response = await (method == 'GET'
        ? http.get(uri, headers: headers)
        : http.post(uri, headers: headers, body: jsonEncode(body ?? {})));

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) await logout();
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      throw AdminDispatchApiException(message);
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<Map<String, dynamic>> listBookings({
    String? search,
    String? status,
    String? assignmentState,
    String? serviceDateFrom,
    String? serviceDateTo,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (assignmentState != null && assignmentState.isNotEmpty) {
      query['assignmentState'] = assignmentState;
    }
    if (serviceDateFrom != null) query['serviceDateFrom'] = serviceDateFrom;
    if (serviceDateTo != null) query['serviceDateTo'] = serviceDateTo;
    final data = await _request('GET', '/admin/bookings', query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    final data = await _request('GET', '/admin/bookings/$bookingNumber');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> listDrivers() async {
    final data = await _request('GET', '/admin/drivers');
    if (data is List) return data;
    if (data is Map) return data['items'] as List<dynamic>? ?? [];
    return [];
  }

  Future<Map<String, dynamic>> assignDriver(String bookingNumber, int driverId) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/assign-driver',
      body: {'driverId': driverId},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> reassignDriver(
    String bookingNumber,
    int driverId,
    String reason,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/reassign-driver',
      body: {'driverId': driverId, 'reason': reason},
    );
    return Map<String, dynamic>.from(data as Map);
  }
}
