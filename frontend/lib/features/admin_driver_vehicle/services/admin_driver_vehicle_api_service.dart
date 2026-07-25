import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/admin_driver_vehicle_models.dart';

class AdminDriverVehicleApiException implements Exception {
  const AdminDriverVehicleApiException(
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

class AdminDriverVehicleApiService {
  AdminDriverVehicleApiService({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? adminTokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _adminTokenProvider = adminTokenProvider;

  final http.Client _client;
  final String _baseUrl;
  final Future<String?> Function()? _adminTokenProvider;

  String get _base => '$_baseUrl/api/v1';

  Future<String?> _adminToken() async {
    final provider = _adminTokenProvider;
    if (provider != null) return provider();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_access_token');
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  Never _throw(http.Response response, dynamic decoded) {
    final message = decoded is Map
        ? decoded['message'] as String? ?? 'Request failed'
        : 'Request failed';
    final errorCode = decoded is Map
        ? decoded['error_code'] as String? ?? decoded['code'] as String?
        : null;
    throw AdminDriverVehicleApiException(
      message,
      errorCode: errorCode,
      statusCode: response.statusCode,
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await _adminToken();
    if (token == null || token.isEmpty) {
      throw const AdminDriverVehicleApiException(
        'Please log in',
        statusCode: 401,
        errorCode: 'UNAUTHORIZED',
      );
    }
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    late final http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
      case 'POST':
        headers['Content-Type'] = 'application/json';
        response = await _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        );
      default:
        throw AdminDriverVehicleApiException('Unsupported method $method');
    }
    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throw(response, decoded);
    }
    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<AdminDriverVehicleListResult> listVehicles({
    String status = 'PENDING',
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status.isNotEmpty) 'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final data = await _request('GET', '/admin/driver-vehicles', query: query);
    return AdminDriverVehicleListResult.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<Map<String, dynamic>> approve(int id) async {
    final data = await _request(
      'POST',
      '/admin/driver-vehicles/$id/approve',
      body: const {},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> reject(
    int id, {
    required String rejectionReason,
  }) async {
    final data = await _request(
      'POST',
      '/admin/driver-vehicles/$id/reject',
      body: {'rejectionReason': rejectionReason},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Uint8List> fetchFileBytes(String urlPath) async {
    final token = await _adminToken();
    if (token == null || token.isEmpty) {
      throw const AdminDriverVehicleApiException(
        'Please log in',
        statusCode: 401,
        errorCode: 'UNAUTHORIZED',
      );
    }
    final uri = urlPath.startsWith('http')
        ? Uri.parse(urlPath)
        : Uri.parse('$_baseUrl$urlPath');
    final response = await _client.get(
      uri,
      headers: {
        'Accept': '*/*',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throw(response, _decode(response));
    }
    return response.bodyBytes;
  }
}
