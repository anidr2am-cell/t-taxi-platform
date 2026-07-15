import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../../chat/utils/client_message_id.dart' as chat_ids;

class AdminChatApiException implements Exception {
  const AdminChatApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminChatApiService {
  const AdminChatApiService();

  static const _tokenKey = 'admin_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  static String newClientMessageId() => chat_ids.newClientMessageId('admin');

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const AdminChatApiException('Please log in');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> listChats({
    bool unreadOnly = false,
    String? search,
    bool archived = false,
  }) async {
    final query = <String, String>{};
    if (unreadOnly) query['unreadOnly'] = 'true';
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (archived) query['archived'] = 'true';
    final uri = Uri.parse(
      '$_base/admin/chats',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: await _headers());
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminChatApiException(
        decoded['message'] as String? ?? 'Request failed',
      );
    }
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> getRoom(String bookingNumber) async {
    final response = await http.get(
      Uri.parse('$_base/admin/chats/$bookingNumber'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Future<List<dynamic>> listMessages(String bookingNumber) async {
    final response = await http.get(
      Uri.parse('$_base/admin/chats/$bookingNumber/messages'),
      headers: await _headers(),
    );
    final data = _decode(response);
    return data['items'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> sendMessage({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/admin/chats/$bookingNumber/messages'),
      headers: await _headers(),
      body: jsonEncode({'text': text, 'clientMessageId': clientMessageId}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> markRead({
    required String bookingNumber,
    required int upToMessageId,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/admin/chats/$bookingNumber/read'),
      headers: await _headers(),
      body: jsonEncode({'upToMessageId': upToMessageId}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> hideMessage({
    required int messageId,
    String reason = 'ADMIN_MODERATION',
  }) async {
    final response = await http.post(
      Uri.parse('$_base/admin/chats/messages/$messageId/hide'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> restoreMessage({required int messageId}) async {
    final response = await http.post(
      Uri.parse('$_base/admin/chats/messages/$messageId/restore'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> archiveThreads(
    List<String> bookingNumbers,
  ) async {
    final response = await http.post(
      Uri.parse('$_base/admin/chats/archive'),
      headers: await _headers(),
      body: jsonEncode({'bookingNumbers': bookingNumbers}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> restoreThread(String bookingNumber) async {
    final response = await http.post(
      Uri.parse('$_base/admin/chats/$bookingNumber/restore'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminChatApiException(
        decoded['message'] as String? ?? 'Request failed',
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}
