import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminPricingApiException implements Exception {
  const AdminPricingApiException(this.message, {this.fieldErrors});

  final String message;
  final Map<String, String>? fieldErrors;

  @override
  String toString() => message;
}

class AdminPricingApiService {
  const AdminPricingApiService();

  static const _tokenKey = 'admin_access_token';
  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

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
      throw const AdminPricingApiException('Please log in');
    }

    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'PATCH':
        response = await http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw AdminPricingApiException('Unsupported method: $method');
    }

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      Map<String, String>? fieldErrors;
      if (decoded is Map && decoded['errors'] is List) {
        fieldErrors = {};
        for (final item in decoded['errors'] as List) {
          if (item is Map) {
            final field = item['field'] as String? ?? 'general';
            final message = item['message'] as String? ?? 'Invalid value';
            fieldErrors[field] = message;
          }
        }
      }
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      throw AdminPricingApiException(message, fieldErrors: fieldErrors);
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<Map<String, dynamic>> getSummary() async {
    final data = await _request('GET', '/admin/pricing/summary');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> listRoutes({bool includeInactive = true}) async {
    final data = await _request('GET', '/admin/routes', query: {
      'includeInactive': includeInactive.toString(),
    });
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createRoute(Map<String, dynamic> body) async {
    final data = await _request('POST', '/admin/routes', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateRoute(int id, Map<String, dynamic> body) async {
    final data = await _request('PATCH', '/admin/routes/$id', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> copyRoute(int id, Map<String, dynamic> body) async {
    final data = await _request('POST', '/admin/routes/$id/copy', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> listVehiclePrices({
    int? routeId,
    bool includeInactive = true,
  }) async {
    final query = <String, String>{'includeInactive': includeInactive.toString()};
    if (routeId != null) query['routeId'] = '$routeId';
    final data = await _request('GET', '/admin/vehicle-prices', query: query);
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createVehiclePrice(Map<String, dynamic> body) async {
    final data = await _request('POST', '/admin/vehicle-prices', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateVehiclePrice(int id, Map<String, dynamic> body) async {
    final data = await _request('PATCH', '/admin/vehicle-prices/$id', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> listChargePolicies({bool includeInactive = true}) async {
    final data = await _request('GET', '/admin/charge-policies', query: {
      'includeInactive': includeInactive.toString(),
    });
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createChargePolicy(Map<String, dynamic> body) async {
    final data = await _request('POST', '/admin/charge-policies', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateChargePolicy(int id, Map<String, dynamic> body) async {
    final data = await _request('PATCH', '/admin/charge-policies/$id', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> simulatePricing(Map<String, dynamic> body) async {
    final data = await _request('POST', '/admin/pricing/simulate', body: body);
    return Map<String, dynamic>.from(data as Map);
  }
}

const kServiceTypes = [
  'AIRPORT_PICKUP',
  'AIRPORT_DROPOFF',
  'CITY_TRANSFER',
  'GOLF_TRANSFER',
];

const kVehicleTypes = [
  'SEDAN',
  'SUV',
  'VIP_SUV',
  'VAN',
  'VIP_VAN',
  'LUXURY',
];

const kChargePolicyTypes = [
  'NAME_SIGN',
  'WAITING',
  'PARKING',
  'TOLL',
  'HOLIDAY',
  'NIGHT',
  'AIRPORT',
];

const kCalculationTypes = [
  'FIXED',
  'PERCENT_OF_BASE',
  'PERCENT_OF_SUBTOTAL',
];

String vehiclePriceStatus(Map<String, dynamic> price) {
  final isActive = price['isActive'] == true;
  if (!isActive) return 'inactive';

  final now = DateTime.now().toUtc();
  final fromRaw = price['effectiveFrom'];
  final toRaw = price['effectiveTo'];
  final from = fromRaw != null ? DateTime.tryParse(fromRaw as String)?.toUtc() : null;
  final to = toRaw != null ? DateTime.tryParse(toRaw as String)?.toUtc() : null;

  if (to != null && now.isAfter(to)) return 'expired';
  if (from != null && now.isBefore(from)) return 'future';
  return 'current';
}

String chargePolicyStatus(Map<String, dynamic> policy) {
  final isActive = policy['isActive'] == true;
  if (!isActive) return 'inactive';

  final now = DateTime.now().toUtc();
  final fromRaw = policy['effectiveFrom'];
  final toRaw = policy['effectiveTo'];
  final from = fromRaw != null ? DateTime.tryParse(fromRaw as String)?.toUtc() : null;
  final to = toRaw != null ? DateTime.tryParse(toRaw as String)?.toUtc() : null;

  if (to != null && now.isAfter(to)) return 'expired';
  if (from != null && now.isBefore(from)) return 'future';
  return 'current';
}
