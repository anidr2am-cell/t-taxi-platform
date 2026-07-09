import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';

class BookingChatApiException implements Exception {
  const BookingChatApiException(
    this.message, {
    this.errorCode,
    this.statusCode,
  });
  final String message;
  final String? errorCode;
  final int? statusCode;
  @override
  String toString() => message;
}

class BookingChatApi {
  const BookingChatApi();

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Map<String, String> _headers({
    String? guestAccessToken,
    String? customerAccessToken,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (customerAccessToken != null && customerAccessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerAccessToken';
    }
    if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      headers['X-Guest-Access-Token'] = guestAccessToken;
    }
    return headers;
  }

  static String newClientMessageId() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  Future<Map<String, dynamic>> getRoom({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$_base/bookings/$bookingNumber/chat'),
      headers: _headers(
        guestAccessToken: guestAccessToken,
        customerAccessToken: customerAccessToken,
      ),
    );
    return _decode(response);
  }

  Future<List<dynamic>> listMessages({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final data = await _request(
      bookingNumber: bookingNumber,
      pathSuffix: '/messages',
      guestAccessToken: guestAccessToken,
      customerAccessToken: customerAccessToken,
    );
    return data['items'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> sendMessage({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/bookings/$bookingNumber/chat/messages'),
      headers: _headers(
        guestAccessToken: guestAccessToken,
        customerAccessToken: customerAccessToken,
      ),
      body: jsonEncode({'text': text, 'clientMessageId': clientMessageId}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> sendPickupAlert({
    required String bookingNumber,
    required String guestAccessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/bookings/$bookingNumber/pickup-alert'),
      headers: _headers(guestAccessToken: guestAccessToken),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> markRead({
    required String bookingNumber,
    required int upToMessageId,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/bookings/$bookingNumber/chat/read'),
      headers: _headers(
        guestAccessToken: guestAccessToken,
        customerAccessToken: customerAccessToken,
      ),
      body: jsonEncode({'upToMessageId': upToMessageId}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _request({
    required String bookingNumber,
    required String pathSuffix,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$_base/bookings/$bookingNumber/chat$pathSuffix'),
      headers: _headers(
        guestAccessToken: guestAccessToken,
        customerAccessToken: customerAccessToken,
      ),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw BookingChatApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
        errorCode: decoded is Map ? decoded['error_code'] as String? : null,
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}
