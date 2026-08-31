import '../../../core/network/api_exception.dart';
import '../../auth/services/customer_api_errors.dart';
import '../../auth/services/customer_session.dart';
import '../models/guest_booking_lookup_result.dart';

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
    CustomerSession? session,
  }) : _session = session ?? CustomerSession();

  final CustomerSession _session;

  Future<CustomerBookingsPageResult> listMyBookings({
    int page = 1,
    int limit = 20,
  }) async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const CustomerBookingsApiException('Authentication required');
    }

    try {
      final decoded = await _session.apiClient.getJson(
        '/customer/bookings',
        bearerToken: session.accessToken,
        queryParameters: {
          'page': '$page',
          'limit': '$limit',
        },
      );

      final data = decoded['data'] as Map?;
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
    } on ApiException catch (error) {
      throw CustomerBookingsApiException(
        customerApiErrorMessage(error, fallback: 'Unable to load bookings'),
        statusCode: error.statusCode,
      );
    }
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
