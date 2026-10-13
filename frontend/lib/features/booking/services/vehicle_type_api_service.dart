import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';

class VehicleTypeApiService {
  VehicleTypeApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<List<String>> listActiveCodes() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/v1/vehicles/types'),
      headers: const {'Accept': 'application/json'},
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw StateError('Vehicle type request failed');
    }
    final data = decoded is Map ? decoded['data'] : decoded;
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => row['code']?.toString().trim().toUpperCase() ?? '')
        .where((code) => code.isNotEmpty && code != 'VIP_VAN')
        .toList(growable: false);
  }
}
