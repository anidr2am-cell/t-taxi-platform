import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminCouponApiException implements Exception {
  const AdminCouponApiException(this.message, {this.errorCode});

  final String message;
  final String? errorCode;

  @override
  String toString() => message;
}

class AdminCustomerSearchResult {
  const AdminCustomerSearchResult({
    required this.id,
    this.name,
    this.phone,
    this.email,
  });

  final int id;
  final String? name;
  final String? phone;
  final String? email;

  factory AdminCustomerSearchResult.fromJson(Map<String, dynamic> json) {
    return AdminCustomerSearchResult(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }
}

class AdminIssuedCouponItem {
  const AdminIssuedCouponItem({
    required this.id,
    required this.title,
    required this.discountAmount,
    required this.status,
    this.issuedAt,
    this.usedAt,
    required this.customer,
  });

  final int id;
  final String title;
  final int discountAmount;
  final String status;
  final String? issuedAt;
  final String? usedAt;
  final AdminCustomerSearchResult customer;

  factory AdminIssuedCouponItem.fromJson(Map<String, dynamic> json) {
    return AdminIssuedCouponItem(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      discountAmount: json['discountAmount'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      issuedAt: json['issuedAt'] as String?,
      usedAt: json['usedAt'] as String?,
      customer: AdminCustomerSearchResult.fromJson(
        Map<String, dynamic>.from(json['customer'] as Map? ?? const {}),
      ),
    );
  }
}

class AdminCouponApiService {
  const AdminCouponApiService({http.Client? client, String? baseUrl})
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

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminCouponApiException('Please log in');
    }

    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    final client = _client ?? http.Client();
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await client.get(uri, headers: headers);
        break;
      case 'POST':
        response = await client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'DELETE':
        response = await client.delete(uri, headers: headers);
        break;
      default:
        throw AdminCouponApiException('Unsupported method: $method');
    }

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      throw AdminCouponApiException(
        message,
        errorCode: decoded is Map ? decoded['error_code'] as String? : null,
      );
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<List<AdminCustomerSearchResult>> searchCustomers(String query) async {
    final data = await _request(
      'GET',
      '/admin/customers/search',
      query: {'query': query.trim()},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => AdminCustomerSearchResult.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<AdminIssuedCouponItem> issueCoupon({
    required int customerUserId,
    required String title,
    required int discountAmount,
  }) async {
    final data = await _request(
      'POST',
      '/admin/coupons',
      body: {
        'customerUserId': customerUserId,
        'title': title.trim(),
        'discountAmount': discountAmount,
      },
    );
    return AdminIssuedCouponItem.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<void> cancelCoupon(int couponId) async {
    await _request('DELETE', '/admin/coupons/$couponId');
  }

  Future<List<AdminIssuedCouponItem>> listRecentCoupons({int limit = 20}) async {
    final data = await _request(
      'GET',
      '/admin/coupons',
      query: {'limit': '$limit'},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => AdminIssuedCouponItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }
}
