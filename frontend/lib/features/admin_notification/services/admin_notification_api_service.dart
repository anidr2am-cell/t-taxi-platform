import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminNotificationApiException implements Exception {
  const AdminNotificationApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminNotificationApiService {
  const AdminNotificationApiService();

  static const _tokenKey = 'admin_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<dynamic> _request(String method, String path, {Map<String, String>? query}) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminNotificationApiException('Please log in');
    }
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
    final response = await (method == 'GET'
        ? http.get(uri, headers: headers)
        : http.post(uri, headers: headers));
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminNotificationApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
      );
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<Map<String, dynamic>> listNotifications({
    bool? unreadOnly,
    String? notificationType,
  }) async {
    final query = <String, String>{};
    if (unreadOnly == true) query['unreadOnly'] = 'true';
    if (notificationType != null) query['notificationType'] = notificationType;
    final data = await _request('GET', '/admin/notifications', query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<int> getUnreadCount() async {
    final data = await _request('GET', '/admin/notifications/unread-count');
    return Map<String, dynamic>.from(data as Map)['unreadCount'] as int? ?? 0;
  }

  Future<void> markRead(int notificationId) async {
    await _request('POST', '/admin/notifications/$notificationId/read');
  }

  Future<void> markAllRead() async {
    await _request('POST', '/admin/notifications/read-all');
  }
}
