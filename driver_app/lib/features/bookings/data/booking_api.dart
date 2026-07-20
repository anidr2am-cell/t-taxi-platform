import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';

abstract interface class BookingDataSource {
  Future<Map<String, dynamic>> getTodayBookings();
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber);
  Future<Map<String, dynamic>> acceptBooking(String bookingNumber);
}

class BookingApi implements BookingDataSource {
  const BookingApi({required ApiClient client, required TokenStorage storage})
    : _client = client,
      _storage = storage;

  final ApiClient _client;
  final TokenStorage _storage;

  @override
  Future<Map<String, dynamic>> getTodayBookings() async {
    return _client.getJson(
      '/api/v1/driver/bookings/today',
      bearerToken: await _accessToken(),
    );
  }

  @override
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    final safeNumber = _validatedBookingNumber(bookingNumber);
    return _client.getJson(
      '/api/v1/driver/bookings/${Uri.encodeComponent(safeNumber)}',
      bearerToken: await _accessToken(),
    );
  }

  @override
  Future<Map<String, dynamic>> acceptBooking(String bookingNumber) async {
    final safeNumber = _validatedBookingNumber(bookingNumber);
    return _client.postJson(
      '/api/v1/driver/bookings/${Uri.encodeComponent(safeNumber)}/accept',
      bearerToken: await _accessToken(),
    );
  }

  String _validatedBookingNumber(String bookingNumber) {
    if (!RegExp(r'^TX\d{12}$').hasMatch(bookingNumber)) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return bookingNumber;
  }

  Future<String> _accessToken() async {
    final token = (await _storage.read())?.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException(ApiFailureKind.unauthorized);
    }
    return token;
  }
}
