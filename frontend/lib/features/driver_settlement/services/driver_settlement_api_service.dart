import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class DriverSettlementApiException implements Exception {
  const DriverSettlementApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriverSettlementApiService {
  const DriverSettlementApiService();

  static const _tokenKey = 'driver_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<dynamic> _get(String path) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const DriverSettlementApiException('Please log in again');
    }
    final response = await http.get(
      Uri.parse('$_base$path'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw DriverSettlementApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
      );
    }
    return decoded is Map ? decoded['data'] : decoded;
  }

  Future<dynamic> _postFile(String path, List<int> bytes, String filename) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const DriverSettlementApiException('Please log in again');
    }
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
    final uri = Uri.parse('$_base$path');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(mimeType),
    ));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    final decoded = jsonDecode(body);
    if (streamed.statusCode >= 400) {
      throw DriverSettlementApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Upload failed' : 'Upload failed',
      );
    }
    return decoded is Map ? decoded['data'] : decoded;
  }

  Future<List<dynamic>> listSettlements() async {
    final data = await _get('/driver/settlements');
    if (data is Map) return data['items'] as List<dynamic>? ?? [];
    return [];
  }

  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    final data = await _get('/driver/settlements/$bookingNumber');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> uploadReceipt(String bookingNumber, List<int> bytes, String filename) async {
    final data = await _postFile('/driver/settlements/$bookingNumber/receipt', bytes, filename);
    return Map<String, dynamic>.from(data as Map);
  }
}
