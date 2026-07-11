import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
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
    final token = await _adminToken();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$_base/admin/settings/images/$kind'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
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
    if (token == null || token.isEmpty) throw Exception('Please log in');
    return token;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(
        decoded is Map
            ? decoded['message'] ?? 'Request failed'
            : 'Request failed',
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}
