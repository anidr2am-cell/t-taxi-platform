import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/app_config.dart';
import '../models/booking_create_result.dart';
import '../models/pricing_result.dart';
import '../models/vehicle_recommendation.dart';

class BookingApiException implements Exception {
  final String message;
  final String? errorCode;

  BookingApiException(this.message, [this.errorCode]);

  @override
  String toString() => message;
}

class BookingApiService {
  static final BookingApiService _instance = BookingApiService._();
  factory BookingApiService() => _instance;
  BookingApiService._();

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    http.Response response;

    if (method == 'GET') {
      response = await http.get(uri);
    } else {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body ?? {}),
      );
    }

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? (decoded['message'] as String? ?? 'Request failed')
          : 'Request failed';
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      throw BookingApiException(message, code);
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<VehicleRecommendation> recommendVehicle({
    required int adults,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) async {
    final data = await _request('POST', '/bookings/vehicle/recommend', body: {
      'adults': adults,
      'children': children,
      'infants': infants,
      'luggage20': luggage20,
      'luggage24': luggage24,
      'golfBags': golfBags,
      'specialLuggageCount': specialLuggageCount,
    });
    return VehicleRecommendation.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<PricingResult> calculatePricing({
    required String serviceTypeCode,
    required String vehicleTypeCode,
    int vehicleCount = 1,
    String? originAirportIata,
    String? destinationRegion,
    String? originLocationCode,
    String? destinationLocationCode,
    bool nameSign = false,
    String? scheduledPickupAt,
  }) async {
    final body = <String, dynamic>{
      'serviceTypeCode': serviceTypeCode,
      'vehicleTypeCode': vehicleTypeCode,
      'vehicleCount': vehicleCount,
      'options': {'nameSign': nameSign},
    };
    if (originAirportIata != null) body['originAirportIata'] = originAirportIata;
    if (destinationRegion != null) body['destinationRegion'] = destinationRegion;
    if (originLocationCode != null) body['originLocationCode'] = originLocationCode;
    if (destinationLocationCode != null) {
      body['destinationLocationCode'] = destinationLocationCode;
    }
    if (scheduledPickupAt != null) body['scheduledPickupAt'] = scheduledPickupAt;

    final data = await _request('POST', '/bookings/pricing/calculate', body: body);
    return PricingResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BookingCreateResult> createBooking(Map<String, dynamic> body) async {
    final data = await _request('POST', '/bookings', body: body);
    return BookingCreateResult.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
