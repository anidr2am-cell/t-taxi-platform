import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class PlatformSettingsApiService {
  const PlatformSettingsApiService();

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Uri assetUri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Future<Map<String, dynamic>> getPublic() => _get('/settings/public');

  Future<Map<String, dynamic>> getAdmin() =>
      _get('/admin/settings', admin: true);

  Future<Map<String, dynamic>> update(Map<String, String> values) async {
    final token = await _adminToken();
    final response = await http.put(
      Uri.parse('$_base/admin/settings'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(values),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadImage(
    String kind,
    Uint8List bytes,
    String filename,
  ) async {
    final contentType = settingsImageContentTypeFor(filename, bytes);
    if (contentType == null) {
      throw const PlatformSettingsApiException(
        'Only PNG and JPEG images are supported',
        errorCode: 'INVALID_SETTINGS_IMAGE',
        statusCode: 400,
      );
    }
    final token = await _adminToken();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$_base/admin/settings/images/$kind'),
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
    return _decode(await http.Response.fromStream(await request.send()));
  }

  Future<Map<String, dynamic>> _get(String path, {bool admin = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (admin) headers['Authorization'] = 'Bearer ${await _adminToken()}';
    return _decode(await http.get(Uri.parse('$_base$path'), headers: headers));
  }

  Future<String> _adminToken() async {
    final token = (await SharedPreferences.getInstance()).getString(
      'admin_access_token',
    );
    if (token == null || token.isEmpty) {
      throw const PlatformSettingsApiException(
        'Please log in',
        statusCode: 401,
      );
    }
    return token;
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw PlatformSettingsApiException(
        'Image upload failed. Please try again.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw PlatformSettingsApiException(
        decoded is Map
            ? decoded['message']?.toString() ?? 'Request failed'
            : 'Request failed',
        errorCode: decoded is Map ? decoded['code']?.toString() : null,
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}

class PlatformSettingsApiException implements Exception {
  const PlatformSettingsApiException(
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

MediaType? settingsImageContentTypeFor(String filename, Uint8List bytes) {
  final extension = _extension(filename);
  final signature = _detectImageSignature(bytes);
  if (signature == 'png' && extension == 'png') {
    return MediaType.parse('image/png');
  }
  if (signature == 'jpeg' && (extension == 'jpg' || extension == 'jpeg')) {
    return MediaType.parse('image/jpeg');
  }
  return null;
}

String _extension(String filename) {
  final safeName = filename
      .split(RegExp(r'[?#]'))
      .first
      .split(RegExp(r'[\\/]'))
      .last;
  final dot = safeName.lastIndexOf('.');
  if (dot < 0 || dot == safeName.length - 1) return '';
  return safeName.substring(dot + 1).toLowerCase();
}

String? _detectImageSignature(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpeg';
  }
  return null;
}
