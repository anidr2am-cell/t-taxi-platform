import '../booking/utils/booking_status_display.dart';
import 'driver_trip_flow.dart';
import 'services/driver_api_service.dart';
import 'models/driver_booking.dart';

/// Job list grouping for driver today view.
enum DriverJobGroup { active, upcoming, completed }

/// Whether a SETTLEMENT_PENDING booking still needs driver settlement action.
enum SettlementActionHint { actionRequired, waitingForAdmin, unknown }

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

  /// Priority for the single "current trip" card on the Today home screen.
  ///
  /// When [settlementsByBooking] is available, action-required SETTLEMENT_PENDING
  /// is ranked above in-progress trips; waiting-for-admin SETTLEMENT_PENDING is
  /// ranked below DRIVER_ASSIGNED. Without settlement data, all SETTLEMENT_PENDING
  /// bookings share the highest active priority.
  static SettlementActionHint settlementActionHint(
    Map<String, dynamic>? settlement,
  ) {
    if (settlement == null) return SettlementActionHint.unknown;
    final commissionStatus = settlement['commissionStatus'] as String? ?? '';
    final receiptStatus = settlement['receiptStatus'] as String? ?? '';
    if (commissionStatus == 'RECEIPT_SUBMITTED' ||
        receiptStatus == 'SUBMITTED' ||
        settlement['receiptUrl'] != null) {
      return SettlementActionHint.waitingForAdmin;
    }
    if (commissionStatus == 'PENDING' ||
        commissionStatus == 'REJECTED' ||
        commissionStatus == 'OVERDUE') {
      return SettlementActionHint.actionRequired;
    }
    return SettlementActionHint.unknown;
  }

  static bool settlementNeedsDriverAction(Map<String, dynamic>? settlement) {
    final hint = settlementActionHint(settlement);
    return hint == SettlementActionHint.actionRequired ||
        hint == SettlementActionHint.unknown;
  }

  static int _currentTripPriority(
    DriverBooking booking, {
    Map<String, Map<String, dynamic>>? settlementsByBooking,
  }) {
    switch (booking.status) {
      case 'SETTLEMENT_PENDING':
        if (settlementsByBooking != null) {
          final settlement = settlementsByBooking[booking.bookingNumber];
          if (!settlementNeedsDriverAction(settlement)) {
            return 50;
          }
        }
        return 0;
      case 'PICKED_UP':
        return 10;
      case 'DRIVER_ARRIVED':
        return 20;
      case 'ON_ROUTE':
        return 30;
      case 'DRIVER_ASSIGNED':
        return 40;
      default:
        if (groupForStatus(booking.status) == DriverJobGroup.upcoming) {
          return 60;
        }
        return 100;
    }
  }

  static DriverBooking? selectCurrentTrip(
    List<DriverBooking> items, {
    Map<String, Map<String, dynamic>>? settlementsByBooking,
  }) {
    if (items.isEmpty) return null;

    final prioritized = items
        .where(
          (booking) =>
              _currentTripPriority(
                booking,
                settlementsByBooking: settlementsByBooking,
              ) <
              100,
        )
        .toList();
    if (prioritized.isNotEmpty) {
      prioritized.sort((a, b) {
        final priority = _currentTripPriority(
          a,
          settlementsByBooking: settlementsByBooking,
        ).compareTo(
          _currentTripPriority(
            b,
            settlementsByBooking: settlementsByBooking,
          ),
        );
        if (priority != 0) return priority;
        final time = a.pickupTime.compareTo(b.pickupTime);
        if (time != 0) return time;
        return a.bookingNumber.compareTo(b.bookingNumber);
      });
      return prioritized.first;
    }

    final upcoming = items
        .where((b) => groupForStatus(b.status) == DriverJobGroup.upcoming)
        .toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) {
      final time = a.pickupTime.compareTo(b.pickupTime);
      if (time != 0) return time;
      return a.bookingNumber.compareTo(b.bookingNumber);
    });
    return upcoming.first;
  }

  static List<DriverBooking> remainingTodayTrips(
    List<DriverBooking> items, {
    DriverBooking? current,
  }) {
    if (current == null) {
      return items
          .where((b) => groupForStatus(b.status) != DriverJobGroup.completed)
          .toList();
    }
    return items
        .where(
          (b) =>
              b.bookingNumber != current.bookingNumber &&
              groupForStatus(b.status) != DriverJobGroup.completed,
        )
        .toList();
  }

  static List<DriverBooking> completedTodayTrips(List<DriverBooking> items) {
    return items
        .where((b) => groupForStatus(b.status) == DriverJobGroup.completed)
        .toList();
  }

  static String? statusGuidanceKey(String status) {
    switch (status) {
      case 'DRIVER_ASSIGNED':
        return 'driver_status_guidance_assigned';
      case 'ON_ROUTE':
        return 'driver_status_guidance_on_route';
      case 'DRIVER_ARRIVED':
        return 'driver_status_guidance_arrived';
      case 'PICKED_UP':
        return 'driver_status_guidance_picked_up';
      case 'SETTLEMENT_PENDING':
        return 'driver_status_guidance_settlement';
      default:
        return null;
    }
  }

  static String todayPrimaryCtaKey(
    DriverBooking booking, {
    Map<String, dynamic>? settlement,
  }) {
    if (booking.status != 'SETTLEMENT_PENDING') {
      return 'driver_today_cta_continue';
    }
    return switch (settlementActionHint(settlement)) {
      SettlementActionHint.actionRequired => 'driver_today_cta_settlement_submit',
      SettlementActionHint.waitingForAdmin => 'driver_today_cta_settlement_waiting',
      SettlementActionHint.unknown => 'driver_today_cta_settlement',
    };
  }

  static String navigateTargetAddress(DriverBooking booking) {
    if (booking.status == 'PICKED_UP') {
      return booking.destination;
    }
    return booking.origin;
  }

  static int countPendingSettlements(List<dynamic> items) {
    return items.where((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final status = item['commissionStatus'] as String? ?? '';
      return status == 'PENDING' ||
          status == 'REJECTED' ||
          status == 'OVERDUE' ||
          status == 'RECEIPT_SUBMITTED';
    }).length;
  }

  static int notificationPriority(Map<String, dynamic> item) {
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    final type = item['notificationType'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final action = item['action'] as String? ?? '';
    final deepLink = item['deepLink'] as String? ?? '';
    final candidates = [
      type,
      category,
      action,
      deepLink,
      payload['type'] as String? ?? '',
      payload['category'] as String? ?? '',
      payload['action'] as String? ?? '',
      payload['deepLink'] as String? ?? '',
    ].map((value) => value.toUpperCase()).join(' ');

    if (candidates.contains('ASSIGN') || candidates.contains('BOOKING')) {
      return 0;
    }
    if (candidates.contains('CHANGE') || candidates.contains('UPDATE')) {
      return 1;
    }
    if (candidates.contains('CHAT') || candidates.contains('MESSAGE')) {
      return 2;
    }
    if (candidates.contains('PICKUP')) {
      return 3;
    }
    if (candidates.contains('COMMISSION') ||
        candidates.contains('RECEIPT') ||
        candidates.contains('SETTLEMENT')) {
      return 4;
    }
    return 5;
  }

  static List<Map<String, dynamic>> sortNotifications(List<dynamic> items) {
    final mapped = items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    mapped.sort((a, b) {
      final readA = a['read'] == true;
      final readB = b['read'] == true;
      if (readA != readB) return readA ? 1 : -1;
      final priority = notificationPriority(a).compareTo(notificationPriority(b));
      if (priority != 0) return priority;
      final createdA = a['createdAt'] as String? ?? '';
      final createdB = b['createdAt'] as String? ?? '';
      return createdB.compareTo(createdA);
    });
    return mapped;
  }
}

bool driverIsAuthError(Object err) {
  if (err is DriverApiException) {
    return err.statusCode == 401 ||
        err.message.toLowerCase().contains('log in');
  }
  return false;
}
