import '../booking/utils/booking_status_display.dart';
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

  /// Next action hint for job cards (operational label key suffix).
  static String? nextActionKey(DriverBooking booking) {
    if (isReadOnly(booking.status)) return null;
    if (booking.allowedActions.contains('START_ON_ROUTE')) {
      return 'driver_action_start_on_route';
    }
    if (booking.allowedActions.contains('MARK_ARRIVED')) {
      return 'driver_action_mark_arrived';
    }
    if (booking.allowedActions.contains('COMPLETE_TRIP')) {
      return 'driver_action_complete_trip';
    }
    if (booking.status == 'DRIVER_ASSIGNED') {
      return 'driver_job_assigned_hint';
    }
    return null;
  }

  static String? primaryActionKey(DriverBooking booking) {
    if (isReadOnly(booking.status)) return null;
    if (booking.allowedActions.contains('START_ON_ROUTE')) {
      return 'driver_action_start_on_route';
    }
    if (booking.allowedActions.contains('MARK_ARRIVED')) {
      return 'driver_action_mark_arrived';
    }
    if (booking.allowedActions.contains('COMPLETE_TRIP')) {
      return 'driver_action_complete_trip';
    }
    return null;
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
      BookingStatusDisplay.statusLabelKey(status);
}

bool driverIsAuthError(Object err) {
  if (err is DriverApiException) {
    return err.statusCode == 401 ||
        err.message.toLowerCase().contains('log in');
  }
  return false;
}
