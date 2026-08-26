import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../booking/models/guest_booking_lookup_result.dart';
import '../../auth/services/auth_token_storage.dart';

class CustomerBookingsApiException implements Exception {
  const CustomerBookingsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CustomerBookingsPageResult {
  const CustomerBookingsPageResult({
    required this.bookings,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<GuestBookingLookupResult> bookings;
  final int total;
  final int page;
  final int limit;
}

class CustomerBookingsApiService {
  CustomerBookingsApiService({
    http.Client? client,
    AuthTokenStorage? tokenStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? AuthTokenStorage(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final AuthTokenStorage _tokenStorage;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  Future<CustomerBookingsPageResult> listMyBookings({
    int page = 1,
    int limit = 20,
  }) async {
    final session = await _tokenStorage.loadSession();
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const CustomerBookingsApiException('Authentication required');
    }

    final uri = Uri.parse('$_base/customer/bookings').replace(
      queryParameters: {
        'page': '$page',
        'limit': '$limit',
      },
    );

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Unable to load bookings'
          : 'Unable to load bookings';
      throw CustomerBookingsApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    final data = decoded is Map ? decoded['data'] as Map? : null;
    if (data == null) {
      throw const CustomerBookingsApiException('Invalid bookings response');
    }

    final rawBookings = data['bookings'];
    final bookings = rawBookings is List
        ? rawBookings
            .whereType<Map>()
            .map(
              (item) => GuestBookingLookupResult.fromCustomerBookingsApiJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList()
        : <GuestBookingLookupResult>[];

    return CustomerBookingsPageResult(
      bookings: bookings,
      total: data['total'] as int? ?? bookings.length,
      page: data['page'] as int? ?? page,
      limit: data['limit'] as int? ?? limit,
    );
  }

  Future<GuestBookingLookupResult> findMyBookingByNumber(
    String bookingNumber,
  ) async {
    final normalized = bookingNumber.trim().toUpperCase();
    var page = 1;
    const limit = 50;

    while (true) {
      final result = await listMyBookings(page: page, limit: limit);
      for (final booking in result.bookings) {
        if (booking.bookingNumber == normalized) {
          return booking;
        }
      }
      if (page * limit >= result.total || result.bookings.isEmpty) {
        break;
      }
      page += 1;
    }

    throw CustomerBookingsApiException(
      'Booking not found',
      statusCode: 404,
    );
  }
}
