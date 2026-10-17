import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/app_config.dart';
Future<Set<String>> Function()? airportCatalogLoader;
Future<Set<String>> registeredAirportCodes() async {
  if (airportCatalogLoader != null) return airportCatalogLoader!();
  final response = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/api/v1/airports')).timeout(const Duration(seconds: 8));
  if(response.statusCode != 200) throw StateError('Airport catalog unavailable');
  final body = jsonDecode(response.body) as Map;
  return (body['data'] as List).map((r)=>(r as Map)['code'].toString()).toSet();
}
