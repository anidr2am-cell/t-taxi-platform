import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';

class AdminHomeBannerApiException implements Exception {
  const AdminHomeBannerApiException(this.message, {this.errorCode, this.statusCode});

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminHomeBannerItem {
  const AdminHomeBannerItem({
    required this.id,
    required this.displayOrder,
    required this.isActive,
    required this.imageUrl,
  });

  final int id;
  final int displayOrder;
  final bool isActive;
  final String imageUrl;

  factory AdminHomeBannerItem.fromJson(Map<String, dynamic> json) {
    return AdminHomeBannerItem(
      id: json['id'] as int? ?? 0,
      displayOrder: json['displayOrder'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }
}

class AdminHomeBannerApiService {
  const AdminHomeBannerApiService({http.Client? client, String? baseUrl})
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
    Map<String, dynamic>? body,
  }) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminHomeBannerApiException('Please log in');
    }

    final uri = Uri.parse('$_base$path');
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
      case 'PATCH':
        response = await client.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'DELETE':
        response = await client.delete(uri, headers: headers);
        break;
      default:
        throw AdminHomeBannerApiException('Unsupported method: $method');
    }

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminHomeBannerApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
        errorCode: decoded is Map ? decoded['error_code'] as String? : null,
        statusCode: response.statusCode,
      );
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<List<AdminHomeBannerItem>> listBanners() async {
    final data = await _request('GET', '/admin/home-banners');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => AdminHomeBannerItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<AdminHomeBannerItem> createBanner({
    required Uint8List bytes,
    required String filename,
    int? displayOrder,
  }) async {
    final contentType = settingsImageContentTypeFor(filename, bytes);
    if (contentType == null) {
      throw const AdminHomeBannerApiException(
        'Only PNG and JPEG images are supported',
        errorCode: 'INVALID_SETTINGS_IMAGE',
        statusCode: 400,
      );
    }

    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminHomeBannerApiException('Please log in');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/admin/home-banners'),
    )
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );
    if (displayOrder != null) {
      request.fields['displayOrder'] = '$displayOrder';
    }

    final client = _client ?? http.Client();
    final response = await http.Response.fromStream(await client.send(request));
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw AdminHomeBannerApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
        errorCode: decoded is Map ? decoded['error_code'] as String? : null,
        statusCode: response.statusCode,
      );
    }

    return AdminHomeBannerItem.fromJson(
      Map<String, dynamic>.from((decoded as Map)['data'] as Map),
    );
  }

  Future<AdminHomeBannerItem> updateBanner({
    required int bannerId,
    bool? isActive,
    int? displayOrder,
  }) async {
    final body = <String, dynamic>{};
    if (isActive != null) body['isActive'] = isActive;
    if (displayOrder != null) body['displayOrder'] = displayOrder;
    final data = await _request('PATCH', '/admin/home-banners/$bannerId', body: body);
    return AdminHomeBannerItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteBanner(int bannerId) async {
    await _request('DELETE', '/admin/home-banners/$bannerId');
  }

  Future<Uint8List> fetchImageBytes(String imageUrl) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminHomeBannerApiException('Please log in', statusCode: 401);
    }
    final uri = imageUrl.startsWith('http')
        ? Uri.parse(imageUrl)
        : Uri.parse('${AppConfig.apiBaseUrl}$imageUrl');
    final client = _client ?? http.Client();
    final response = await client.get(
      uri,
      headers: {
        'Accept': 'image/*',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminHomeBannerApiException(
        'Unable to load image',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }
}
