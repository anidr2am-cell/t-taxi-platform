import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminSupportApiException implements Exception {
  const AdminSupportApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminSupportApiService {
  const AdminSupportApiService();

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
    Map<String, dynamic>? body,
  }) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminSupportApiException('Please log in');
    }
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    late http.Response response;
    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else if (method == 'PATCH') {
      response = await http.patch(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
    } else {
      response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
    }
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminSupportApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
      );
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<Map<String, dynamic>> listInquiries({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (search != null && search.isNotEmpty) query['search'] = search;
    final data = await _request(
      'GET',
      '/admin/support/inquiries',
      query: query,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getInquiry(int id) async {
    final data = await _request('GET', '/admin/support/inquiries/$id');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateStatus(int id, String status) async {
    final data = await _request(
      'PATCH',
      '/admin/support/inquiries/$id/status',
      body: {'status': status},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> sendReply(int id, String message) async {
    final data = await _request(
      'POST',
      '/admin/support/inquiries/$id/messages',
      body: {'message': message},
    );
    return Map<String, dynamic>.from(data as Map);
  }
}
