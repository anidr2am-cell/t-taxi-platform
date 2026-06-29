import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/admin_dashboard_metrics.dart';

class AdminDashboardApiException implements Exception {
  const AdminDashboardApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminDashboardApiService {
  const AdminDashboardApiService({http.Client? client, String? baseUrl})
      : _client = client,
        _baseUrl = baseUrl;

  static const _tokenKey = 'admin_access_token';
  final http.Client? _client;
  final String? _baseUrl;

  String get _base => '${_baseUrl ?? AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<AdminDashboardMetrics> getMetrics() async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminDashboardApiException('Please log in');
    }

    final client = _client ?? http.Client();
    final response = await client.get(
      Uri.parse('$_base/admin/dashboard/metrics'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) await logout();
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      throw AdminDashboardApiException(message);
    }

    final data = decoded is Map ? decoded['data'] as Map? : null;
    if (data == null) {
      throw const AdminDashboardApiException('Invalid dashboard response');
    }
    return AdminDashboardMetrics.fromJson(Map<String, dynamic>.from(data));
  }
}
