import 'booking_api.dart';
import 'booking_models.dart';

abstract interface class BookingReader {
  Future<BookingList> getTodayBookings();
  Future<BookingDetail> getBookingDetail(String bookingNumber);
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
}
