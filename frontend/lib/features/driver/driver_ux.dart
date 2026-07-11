import '../booking/utils/booking_status_display.dart';
import 'driver_trip_flow.dart';
import 'services/driver_api_service.dart';
import 'models/driver_booking.dart';

/// Job list grouping for driver today view.
enum DriverJobGroup { active, upcoming, completed }

class DriverUx {
  static DriverJobGroup groupForStatus(String status) {
    switch (status) {
      case 'DRIVER_ASSIGNED':
      case 'ON_ROUTE':
      case 'DRIVER_ARRIVED':
      case 'PICKED_UP':
      case 'SETTLEMENT_PENDING':
        return DriverJobGroup.active;
      case 'COMPLETED':
      case 'NO_SHOW':
      case 'CANCELLED':
        return DriverJobGroup.completed;
      default:
        return DriverJobGroup.upcoming;
    }
  }

  static bool isTerminal(String status) {
    return status == 'COMPLETED' ||
        status == 'CANCELLED' ||
        status == 'NO_SHOW';
  }

  static bool isReadOnly(String status) => isTerminal(status);

  static bool canMessageCustomer(String status) {
    return status == 'DRIVER_ASSIGNED' ||
        status == 'ON_ROUTE' ||
        status == 'DRIVER_ARRIVED' ||
        status == 'PICKED_UP' ||
        status == 'CONFIRMED';
  }

  static String? nextActionKey(DriverBooking booking) {
    if (isReadOnly(booking.status)) return null;
    return DriverTripFlow.primaryActionLabelKey(booking);
  }

  static String? primaryActionKey(DriverBooking booking) {
    return DriverTripFlow.primaryActionLabelKey(booking);
  }

  static Map<DriverJobGroup, List<DriverBooking>> groupBookings(
    List<DriverBooking> items,
  ) {
    final grouped = <DriverJobGroup, List<DriverBooking>>{
      DriverJobGroup.active: [],
      DriverJobGroup.upcoming: [],
      DriverJobGroup.completed: [],
    };
    for (final booking in items) {
      grouped[groupForStatus(booking.status)]!.add(booking);
    }
    const order = [
      DriverJobGroup.active,
      DriverJobGroup.upcoming,
      DriverJobGroup.completed,
    ];
    for (final g in order) {
      grouped[g]!.sort((a, b) {
        final t = a.pickupTime.compareTo(b.pickupTime);
        if (t != 0) return t;
        return a.bookingNumber.compareTo(b.bookingNumber);
      });
    }
    return grouped;
  }

  static String statusLabelKey(String status) =>
      BookingStatusDisplay.statusLabelKey(
        status,
        audience: BookingStatusAudience.driver,
      );
}

bool driverIsAuthError(Object err) {
  if (err is DriverApiException) {
    return err.statusCode == 401 ||
        err.message.toLowerCase().contains('log in');
  }
  return false;
}
