import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  String get baseUrl => AppConfig.apiBaseUrl;

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final response = await http.get(uri);
    if (response.statusCode >= 400) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Request failed');
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Request failed');
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Request failed');
    }
    return jsonDecode(response.body);
  }

  Future<List<dynamic>> getAirports() => _get('/api/airports') as Future<List<dynamic>>;

  Future<List<dynamic>> getGolfCourses({String? region}) =>
      _get('/api/golf-courses', query: region != null ? {'region': region} : null) as Future<List<dynamic>>;

  Future<List<String>> getGolfRegions() async {
    final result = await _get('/api/golf-regions');
    return (result as List).map((e) => e.toString()).toList();
  }

  Future<Map<String, dynamic>> recommendVehicle(Map<String, dynamic> data) =>
      _post('/api/vehicle/recommend', data) as Future<Map<String, dynamic>>;

  Future<List<dynamic>> getVehiclePrices(String serviceType) =>
      _get('/api/vehicle/prices', query: {'serviceType': serviceType}) as Future<List<dynamic>>;

  Future<Map<String, dynamic>> calculatePrice(Map<String, dynamic> data) =>
      _post('/api/price/calculate', data) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> getFlightInfo(String flightNumber, String date) =>
      _get('/api/flight', query: {'flightNumber': flightNumber, 'date': date}) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> placesAutocomplete(String input, String language) =>
      _get('/api/places/autocomplete', query: {'input': input, 'language': language}) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> placeDetails(String placeId, String language) =>
      _get('/api/places/details', query: {'placeId': placeId, 'language': language}) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> createReservation(Map<String, dynamic> data) =>
      _post('/api/reservations', data) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> getReservation(String number) =>
      _get('/api/reservations/$number') as Future<Map<String, dynamic>>;

  Future<List<dynamic>> listReservations({Map<String, String>? filters}) =>
      _get('/api/reservations', query: filters) as Future<List<dynamic>>;

  Future<Map<String, dynamic>> getDashboard() =>
      _get('/api/admin/dashboard') as Future<Map<String, dynamic>>;

  Future<List<dynamic>> getAdminReservations() =>
      _get('/api/admin/reservations') as Future<List<dynamic>>;

  Future<List<dynamic>> getAdminChats() => _get('/api/admin/chats') as Future<List<dynamic>>;

  Future<List<dynamic>> getChatMessages(String roomId) =>
      _get('/api/admin/chats/$roomId/messages') as Future<List<dynamic>>;

  Future<List<dynamic>> getDrivers() => _get('/api/admin/drivers') as Future<List<dynamic>>;

  Future<List<dynamic>> getAdminVehiclePrices() =>
      _get('/api/admin/vehicle-prices') as Future<List<dynamic>>;

  Future<List<dynamic>> getAdminGolfCourses() =>
      _get('/api/admin/golf-courses') as Future<List<dynamic>>;

  Future<List<dynamic>> getAdminAirports() =>
      _get('/api/admin/airports') as Future<List<dynamic>>;

  Future<Map<String, dynamic>> updateReservationStatus(int id, String status, {int? driverId}) =>
      _patch('/api/admin/reservations/$id', {'status': status, 'driverId': driverId}) as Future<Map<String, dynamic>>;
}
