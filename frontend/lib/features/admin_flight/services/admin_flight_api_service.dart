import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminFlightApiException implements Exception {
  const AdminFlightApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminFlightApiService {
  const AdminFlightApiService();

  static const _tokenKey = 'admin_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
  }) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminFlightApiException('Please log in');
    }
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final response = await (method == 'GET'
        ? http.get(uri, headers: headers)
        : http.post(uri, headers: headers));
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminFlightApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
      );
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<Map<String, dynamic>> listFlights({
    String? date,
    String? flightNumber,
    String? status,
    bool delayedOnly = false,
    String? bookingNumber,
    int page = 1,
    int pageSize = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
    };
    if (date != null && date.isNotEmpty) query['date'] = date;
    if (flightNumber != null && flightNumber.isNotEmpty) {
      query['flightNumber'] = flightNumber;
    }
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (delayedOnly) query['delayedOnly'] = 'true';
    if (bookingNumber != null && bookingNumber.isNotEmpty) {
      query['bookingNumber'] = bookingNumber;
    }
    final data = await _request('GET', '/admin/flights', query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getFlightDetail(int bookingId) async {
    final data = await _request('GET', '/admin/flights/$bookingId');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> syncFlight(int bookingId) async {
    final data = await _request('POST', '/admin/flights/$bookingId/sync');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    final data = await _request('GET', '/admin/flights/sync-status');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> runSyncCycle() async {
    final data = await _request('POST', '/admin/flights/run-sync-cycle');
    return Map<String, dynamic>.from(data as Map);
  }
}
