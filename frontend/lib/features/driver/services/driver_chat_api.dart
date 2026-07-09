import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../../chat/utils/client_message_id.dart' as chat_ids;

class DriverChatApiException implements Exception {
  const DriverChatApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriverChatApi {
  const DriverChatApi();

  static const _tokenKey = 'driver_access_token';
  static const _requestTimeout = Duration(seconds: 15);
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  static String newClientMessageId() =>
      chat_ids.newClientMessageId('driver');

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const DriverChatApiException('Please log in');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getRoom(String bookingNumber) async {
    final response = await http
        .get(
          Uri.parse('$_base/bookings/$bookingNumber/chat'),
          headers: await _headers(),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutResponse);
    return _decode(response);
  }

  Future<List<dynamic>> listMessages(String bookingNumber) async {
    final response = await http
        .get(
          Uri.parse('$_base/bookings/$bookingNumber/chat/messages'),
          headers: await _headers(),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutResponse);
    final data = _decode(response);
    return data['items'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> sendMessage({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/bookings/$bookingNumber/chat/messages'),
          headers: await _headers(),
          body: jsonEncode({'text': text, 'clientMessageId': clientMessageId}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutResponse);
    return _decode(response);
  }

  Future<Map<String, dynamic>> markRead({
    required String bookingNumber,
    required int upToMessageId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/bookings/$bookingNumber/chat/read'),
          headers: await _headers(),
          body: jsonEncode({'upToMessageId': upToMessageId}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutResponse);
    return _decode(response);
  }

  static http.Response _timeoutResponse() {
    return http.Response(
      jsonEncode({'message': '전송 시간이 초과되었습니다. 다시 시도해 주세요.'}),
      408,
      headers: {'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const DriverChatApiException('Request failed');
    }
    if (response.statusCode >= 400) {
      throw DriverChatApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
      );
    }
    if (decoded is! Map) {
      throw const DriverChatApiException('Request failed');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const DriverChatApiException('Request failed');
    }
    return Map<String, dynamic>.from(data);
  }
}
