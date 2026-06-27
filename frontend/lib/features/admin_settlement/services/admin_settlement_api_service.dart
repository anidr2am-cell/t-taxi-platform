import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminSettlementApiException implements Exception {
  const AdminSettlementApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminSettlementApiService {
  const AdminSettlementApiService();

  static const _tokenKey = 'admin_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<dynamic> _request(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminSettlementApiException('Please log in');
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
      if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_tokenKey);
      }
      throw AdminSettlementApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
      );
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<Map<String, dynamic>> listSettlements({
    String? status,
    bool overdueOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null) query['status'] = status;
    if (overdueOnly) query['overdueOnly'] = 'true';
    final data = await _request('GET', '/admin/settlements', query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    final data = await _request('GET', '/admin/settlements/$bookingNumber');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> approve(String bookingNumber) async {
    final data = await _request('POST', '/admin/settlements/$bookingNumber/approve');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> reject(String bookingNumber, String reason) async {
    final data = await _request('POST', '/admin/settlements/$bookingNumber/reject', body: {'reason': reason});
    return Map<String, dynamic>.from(data as Map);
  }
}
