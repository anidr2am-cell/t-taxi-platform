import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/map_provider_config.dart';

class ReverseGeocodingService {
  ReverseGeocodingService({
    http.Client? client,
    String? endpoint,
    Duration timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint ?? MapProviderConfig.reverseGeocodingEndpoint,
       _timeout = timeout;

  final http.Client _client;
  final String _endpoint;
  final Duration _timeout;
  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};

  Future<String?> lookup({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final cacheKey =
        '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}:$language';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    final request = _fetch(
      latitude: latitude,
      longitude: longitude,
      language: language,
    );
    _inFlight[cacheKey] = request;
    final result = await request;
    _inFlight.remove(cacheKey);
    _cache[cacheKey] = result;
    return result;
  }

  Future<String?> _fetch({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'format': 'jsonv2',
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'accept-language': language,
        'addressdetails': '0',
      },
    );
    final headers = <String, String>{'Accept': 'application/json'};
    // Browsers own User-Agent/Referer headers. Native clients identify T-Ride.
    if (!kIsWeb) {
      headers['User-Agent'] = MapProviderConfig.applicationIdentifier;
    }

    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final address = decoded['display_name'];
      return address is String && address.trim().isNotEmpty
          ? address.trim()
          : null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
