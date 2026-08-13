import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../models/contact_channel.dart';

class BookingContactConnectionException implements Exception {
  BookingContactConnectionException(this.message, [this.errorCode]);

  final String message;
  final String? errorCode;

  @override
  String toString() => message;
}

class BookingContactConnectionService {
  BookingContactConnectionService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<List<ContactChannel>> getPublicChannels() async {
    final data = await _request('GET', '/bookings/contact-channels/public');
    final channels = data['channels'];
    if (channels is! List) return const [];
    return channels
        .map((item) => ContactChannel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<ContactConnectionState> getConnection({
    required String bookingNumber,
    required String guestAccessToken,
  }) async {
    final data = await _request(
      'GET',
      '/bookings/$bookingNumber/contact-connection',
      guestAccessToken: guestAccessToken,
    );
    return ContactConnectionState.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ContactConnectionState> startConnection({
    required String bookingNumber,
    required String channel,
    required String guestAccessToken,
  }) async {
    final data = await _request(
      'POST',
      '/bookings/$bookingNumber/contact-connections',
      guestAccessToken: guestAccessToken,
      body: {'channel': channel},
    );
    return ContactConnectionState.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ContactConnectionState> confirmSent({
    required String bookingNumber,
    required String guestAccessToken,
  }) async {
    final data = await _request(
      'POST',
      '/bookings/$bookingNumber/contact-connections/confirm-sent',
      guestAccessToken: guestAccessToken,
    );
    return ContactConnectionState.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? guestAccessToken,
  }) async {
    final uri = Uri.parse('$_base$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      headers['X-Guest-Access-Token'] = guestAccessToken;
    }

    late http.Response response;
    if (method == 'GET') {
      response = await _client.get(uri, headers: headers);
    } else {
      response = await _client.post(
        uri,
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body ?? const {}),
      );
    }

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      throw BookingContactConnectionException(message, code);
    }

    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}
