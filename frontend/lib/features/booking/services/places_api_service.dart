import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/app_config.dart';
import '../models/place_prediction.dart';

class PlacesApiService {
  static final PlacesApiService _instance = PlacesApiService._();
  factory PlacesApiService() => _instance;
  PlacesApiService._({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  PlacesApiService.test({
    required http.Client client,
    required String baseUrl,
  }) : this._(client: client, baseUrl: baseUrl);

  final http.Client _client;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final response = await _client.get(uri);
    final decoded = jsonDecode(response.body);

    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? (decoded['message'] as String? ?? 'Request failed')
          : 'Request failed';
      throw Exception(message);
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<List<PlacePrediction>> autocomplete({
    required String input,
    required String language,
  }) async {
    if (input.trim().length < 2) return [];

    final data = await _get('/places/autocomplete', query: {
      'input': input.trim(),
      'language': language,
    });

    final predictions = data is Map
        ? (data['predictions'] as List<dynamic>? ?? [])
        : (data as List<dynamic>? ?? []);

    return predictions
        .map((item) => PlacePrediction.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((p) => p.placeId.isNotEmpty)
        .toList();
  }

  Future<PlaceDetails> getPlaceDetails({
    required String placeId,
    required String language,
  }) async {
    final data = await _get('/places/details', query: {
      'placeId': placeId,
      'language': language,
    });
    return PlaceDetails.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
