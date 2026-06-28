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
  BookingApiService._({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  BookingApiService.test({
    required http.Client client,
    required String baseUrl,
  }) : this._(client: client, baseUrl: baseUrl);

  final http.Client _client;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    http.Response response;

    if (method == 'GET') {
      response = await _client.get(uri);
    } else {
      response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
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
    final data = await _request(
      'POST',
      '/bookings/vehicle/recommend',
      body: {
        'adults': adults,
        'children': children,
        'infants': infants,
        'luggage20': luggage20,
        'luggage24': luggage24,
        'golfBags': golfBags,
        'specialLuggageCount': specialLuggageCount,
      },
    );
    return VehicleRecommendation.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
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
    int adults = 1,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) async {
    final body = <String, dynamic>{
      'serviceTypeCode': serviceTypeCode,
      'vehicleTypeCode': vehicleTypeCode,
      'vehicleCount': vehicleCount,
      'passengers': {
        'adults': adults,
        'children': children,
        'infants': infants,
      },
      'luggage': {
        'carriers20Inch': luggage20,
        'carriers24InchPlus': luggage24,
        'golfBags': golfBags,
        'specialLuggageCount': specialLuggageCount,
      },
      'options': {'nameSign': nameSign},
    };
    if (originAirportIata != null) {
      body['originAirportIata'] = originAirportIata;
    }
    if (destinationRegion != null) {
      body['destinationRegion'] = destinationRegion;
    }
    if (originLocationCode != null) {
      body['originLocationCode'] = originLocationCode;
    }
    if (destinationLocationCode != null) {
      body['destinationLocationCode'] = destinationLocationCode;
    }
    if (scheduledPickupAt != null) {
      body['scheduledPickupAt'] = scheduledPickupAt;
    }

    final data = await _request(
      'POST',
      '/bookings/pricing/calculate',
      body: body,
    );
    return PricingResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BookingCreateResult> createBooking(Map<String, dynamic> body) async {
    final data = await _request('POST', '/bookings', body: body);
    return BookingCreateResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DropoffQrIssueResult> issueDropoffQr({
    required String bookingNumber,
    required String? guestAccessToken,
  }) async {
    final body = <String, dynamic>{};
    if (guestAccessToken != null) {
      body['guestAccessToken'] = guestAccessToken;
    }

    final data = await _request(
      'POST',
      '/bookings/$bookingNumber/dropoff-qr/issue',
      body: body,
    );
    return DropoffQrIssueResult.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }
}
