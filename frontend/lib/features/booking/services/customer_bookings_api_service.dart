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

class CustomerBookingStatusCounts {
  const CustomerBookingStatusCounts({
    required this.waiting,
    required this.assigned,
    required this.inProgress,
    required this.settlementPending,
    required this.completed,
    required this.reviewPending,
  });

  final int waiting;
  final int assigned;
  final int inProgress;
  final int settlementPending;
  final int completed;
  final int reviewPending;

  factory CustomerBookingStatusCounts.fromJson(Map<String, dynamic> json) {
    return CustomerBookingStatusCounts(
      waiting: json['waiting'] as int? ?? 0,
      assigned: json['assigned'] as int? ?? 0,
      inProgress: json['inProgress'] as int? ?? 0,
      settlementPending: json['settlementPending'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      reviewPending: json['reviewPending'] as int? ?? 0,
    );
  }
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

  Future<CustomerBookingStatusCounts> getStatusCounts() async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const CustomerBookingsApiException('Authentication required');
    }

    try {
      final decoded = await _session.apiClient.getJson(
        '/customer/bookings/status-counts',
        bearerToken: session.accessToken,
      );
      final data = decoded['data'] as Map?;
      if (data == null) {
        throw const CustomerBookingsApiException('Invalid status counts response');
      }
      return CustomerBookingStatusCounts.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on ApiException catch (error) {
      throw CustomerBookingsApiException(
        customerApiErrorMessage(error, fallback: 'Unable to load booking counts'),
        statusCode: error.statusCode,
      );
    }
  }
}
