import '../../../core/network/api_exception.dart';
import 'booking_api.dart';
import 'booking_models.dart';

abstract interface class BookingReader {
  Future<BookingList> getTodayBookings();
  Future<BookingDetail> getBookingDetail(String bookingNumber);
  Future<BookingAcceptance> acceptBooking(String bookingNumber);
  Future<void> startOnRoute(String bookingNumber);
  Future<void> markArrived(String bookingNumber);
  Future<void> markPickedUp(String bookingNumber);
  Future<void> endTrip(String bookingNumber);
  Future<BookingReleaseResult> releaseAssignment(
    String bookingNumber, {
    required String reasonCode,
    String? reasonDetail,
  });
  Future<NameSignPhotoUploadResult> uploadNameSignPhoto(
    String bookingNumber,
    NameSignPhotoFile file,
  );
  Future<List<int>> getNameSignPhoto(String bookingNumber);
}

class BookingRepository implements BookingReader {
  const BookingRepository(this._api);

  final BookingDataSource _api;

  @override
  Future<BookingList> getTodayBookings() async =>
      BookingList.fromEnvelope(await _api.getTodayBookings());

  @override
  Future<BookingDetail> getBookingDetail(String bookingNumber) async =>
      BookingDetail.fromEnvelope(await _api.getBookingDetail(bookingNumber));

  @override
  Future<BookingAcceptance> acceptBooking(String bookingNumber) async =>
      BookingAcceptance.fromEnvelope(await _api.acceptBooking(bookingNumber));

  @override
  Future<void> startOnRoute(String bookingNumber) async {
    _requireSuccess(await _api.startOnRoute(bookingNumber));
  }

  @override
  Future<void> markArrived(String bookingNumber) async {
    _requireSuccess(await _api.markArrived(bookingNumber));
  }

  @override
  Future<void> markPickedUp(String bookingNumber) async {
    _requireSuccess(await _api.markPickedUp(bookingNumber));
  }

  @override
  Future<void> endTrip(String bookingNumber) async {
    _requireSuccess(await _api.endTrip(bookingNumber));
  }

  @override
  Future<BookingReleaseResult> releaseAssignment(
    String bookingNumber, {
    required String reasonCode,
    String? reasonDetail,
  }) async => BookingReleaseResult.fromEnvelope(
    await _api.releaseAssignment(
      bookingNumber,
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    ),
  );

  @override
  Future<NameSignPhotoUploadResult> uploadNameSignPhoto(
    String bookingNumber,
    NameSignPhotoFile file,
  ) async => NameSignPhotoUploadResult.fromEnvelope(
    await _api.uploadNameSignPhoto(bookingNumber, file),
  );

  @override
  Future<List<int>> getNameSignPhoto(String bookingNumber) =>
      _api.getNameSignPhoto(bookingNumber);

  void _requireSuccess(Map<String, dynamic> envelope) {
    if (envelope['success'] != true ||
        envelope['data'] is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
  }
}
