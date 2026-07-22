import '../../../l10n/app_localizations.dart';

/// Server `details.reasonCode` / socket `reasonCode` values for ended assignments.
class DriverAssignmentEndedReason {
  static const customerCancelled = 'CUSTOMER_CANCELLED';
  static const adminCancelled = 'ADMIN_CANCELLED';
  static const driverReleased = 'DRIVER_RELEASED';
  static const reassigned = 'REASSIGNED_TO_ANOTHER_DRIVER';
  static const tripCompleted = 'TRIP_COMPLETED';
  static const noActiveAssignment = 'NO_ACTIVE_ASSIGNMENT';
  static const bookingNotFound = 'BOOKING_NOT_FOUND';

  static String normalize(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    if (value == 'CANCELLED') return customerCancelled;
    return value;
  }

  static String titleKey(String? reasonCode) {
    switch (normalize(reasonCode)) {
      case customerCancelled:
        return 'driver_assignment_ended_customer_title';
      case adminCancelled:
        return 'driver_assignment_ended_admin_title';
      case driverReleased:
        return 'driver_assignment_ended_released_title';
      case reassigned:
        return 'driver_assignment_ended_reassigned_title';
      case tripCompleted:
        return 'driver_assignment_ended_completed_title';
      default:
        return 'driver_assignment_ended_generic_title';
    }
  }

  static String messageKey(String? reasonCode) {
    switch (normalize(reasonCode)) {
      case customerCancelled:
        return 'driver_assignment_ended_customer_message';
      case adminCancelled:
        return 'driver_assignment_ended_admin_message';
      case driverReleased:
        return 'driver_assignment_ended_released_message';
      case reassigned:
        return 'driver_assignment_ended_reassigned_message';
      case tripCompleted:
        return 'driver_assignment_ended_completed_message';
      case bookingNotFound:
        return 'driver_booking_not_found';
      default:
        return 'driver_assignment_ended_generic_message';
    }
  }

  static String snackbarKey(String? reasonCode) {
    switch (normalize(reasonCode)) {
      case customerCancelled:
        return 'driver_assignment_ended_customer_snackbar';
      case adminCancelled:
        return 'driver_assignment_ended_admin_snackbar';
      case driverReleased:
        return 'driver_assignment_ended_released_snackbar';
      case reassigned:
        return 'driver_assignment_ended_reassigned_snackbar';
      default:
        return 'driver_assignment_ended_generic_snackbar';
    }
  }

  static String localize(
    AppLocalizations l10n,
    String? reasonCode, {
    String? bookingNumber,
    bool snackbar = false,
  }) {
    final key = snackbar ? snackbarKey(reasonCode) : messageKey(reasonCode);
    var text = l10n.t(key);
    if (bookingNumber != null && bookingNumber.isNotEmpty) {
      text = text.replaceAll('{bookingNumber}', bookingNumber);
    }
    return text;
  }

  static String localizeTitle(AppLocalizations l10n, String? reasonCode) {
    return l10n.t(titleKey(reasonCode));
  }
}
