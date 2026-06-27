import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminReviewApiException implements Exception {
  const AdminReviewApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminReviewApiService {
  const AdminReviewApiService();

  static const _tokenKey = 'admin_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<dynamic> _request(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminReviewApiException('Please log in');
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
      throw AdminReviewApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
      );
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<Map<String, dynamic>> listReviews({
    String? status,
    int? rating,
    String? search,
  }) async {
    final query = <String, String>{};
    if (status != null) query['status'] = status;
    if (rating != null) query['rating'] = rating.toString();
    if (search != null && search.isNotEmpty) query['search'] = search;
    final data = await _request('GET', '/admin/reviews', query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getReview(int reviewId) async {
    final data = await _request('GET', '/admin/reviews/$reviewId');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> hideReview(int reviewId, String reason) async {
    final data = await _request('POST', '/admin/reviews/$reviewId/hide', body: {'reason': reason});
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> restoreReview(int reviewId) async {
    final data = await _request('POST', '/admin/reviews/$reviewId/restore');
    return Map<String, dynamic>.from(data as Map);
  }
}
