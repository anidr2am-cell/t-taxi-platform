import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/app_config.dart';

class GateArrivalApi {
  GateArrivalApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Future<Map<String, dynamic>> request(
    String number, {
    String? guestToken,
    String? customerToken,
    bool send = false,
  }) async {
    final url = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/v1/bookings/${Uri.encodeComponent(number)}/gate-arrival',
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      if (guestToken?.isNotEmpty == true) 'X-Guest-Access-Token': guestToken!,
      if (customerToken?.isNotEmpty == true)
        'Authorization': 'Bearer $customerToken',
    };
    final response =
        await (send
                ? _client.post(url, headers: headers)
                : _client.get(url, headers: headers))
            .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('gate_arrival_failed');
    final body = jsonDecode(response.body) as Map;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}
