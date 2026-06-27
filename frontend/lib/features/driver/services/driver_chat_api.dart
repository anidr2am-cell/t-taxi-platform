import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class DriverChatApiException implements Exception {
  const DriverChatApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriverChatApi {
  const DriverChatApi();

  static const _tokenKey = 'driver_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  static String newClientMessageId() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    if (token == null || token.isEmpty) throw const DriverChatApiException('Please log in');
    return {'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> getRoom(String bookingNumber) async {
    final response = await http.get(
      Uri.parse('$_base/bookings/$bookingNumber/chat'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Future<List<dynamic>> listMessages(String bookingNumber) async {
    final response = await http.get(
      Uri.parse('$_base/bookings/$bookingNumber/chat/messages'),
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
      Uri.parse('$_base/bookings/$bookingNumber/chat/messages'),
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
      Uri.parse('$_base/bookings/$bookingNumber/chat/read'),
      headers: await _headers(),
      body: jsonEncode({'upToMessageId': upToMessageId}),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw DriverChatApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}
