import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/services/flight_lookup_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('searchFlight calls /api/v1/public/flights/search with query params', () async {
    Uri? requestedUri;
    final api = FlightLookupApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(jsonEncode({
          'success': true,
          'data': {
            'flightNumber': 'TG401',
            'airlineName': 'Thai Airways International',
            'departure': {
              'airportCode': 'BKK',
              'airportName': 'Bangkok Suvarnabhumi',
              'scheduledAt': '2026-07-01T09:30:00Z',
            },
            'arrival': {
              'airportCode': 'SIN',
              'airportName': 'Singapore Changi',
              'scheduledAt': '2026-07-01T12:45:00Z',
              'estimatedAt': '2026-07-01T13:00:00Z',
            },
            'status': 'SCHEDULED',
            'delayMinutes': 15,
          },
        }), 200);
      }),
    );

    final result = await api.searchFlight('TG 401', '2026-07-01');

    expect(result.flightNumber, 'TG401');
    expect(result.airlineName, 'Thai Airways International');
    expect(result.departure.airportCode, 'BKK');
    expect(result.arrival.estimatedAt, '2026-07-01T13:00:00Z');
    expect(requestedUri!.path, '/api/v1/public/flights/search');
    expect(requestedUri!.queryParameters['flightNumber'], 'TG 401');
    expect(requestedUri!.queryParameters['flightDate'], '2026-07-01');
  });

  test('searchFlight throws FlightLookupException with error_code', () async {
    final api = FlightLookupApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async => http.Response(jsonEncode({
        'success': false,
        'error_code': 'FLIGHT_NOT_FOUND',
        'message': 'Flight not found',
      }), 404)),
    );

    expect(
      () => api.searchFlight('TG999', '2026-07-01'),
      throwsA(isA<FlightLookupException>().having(
        (err) => err.errorCode,
        'errorCode',
        'FLIGHT_NOT_FOUND',
      )),
    );
  });
}
