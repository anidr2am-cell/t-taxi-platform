import '../../../l10n/app_localizations.dart';

class BookingCancelDisplay {
  const BookingCancelDisplay._();

  static bool isTerminalStatus(String status) {
    switch (status) {
      case 'CANCELLED':
      case 'COMPLETED':
      case 'NO_SHOW':
        return true;
      default:
        return false;
    }
  }

  static String blockedReasonMessage(
    AppLocalizations l10n,
    String? reason, {
    String? serverMessage,
  }) {
    switch (reason) {
      case 'WITHIN_TWO_HOURS':
        return l10n.t('booking_cancel_blocked_within_two_hours');
      case 'TRIP_STARTED':
        return l10n.t('booking_cancel_blocked_trip_started');
      case 'ALREADY_CANCELLED':
        return l10n.t('booking_cancel_blocked_already_cancelled');
      case 'COMPLETED':
        return l10n.t('booking_cancel_blocked_completed');
      case 'NO_SHOW':
        return l10n.t('booking_cancel_blocked_no_show');
      case 'INVALID_PICKUP_TIME':
        return l10n.t('booking_cancel_blocked_invalid_pickup');
      case 'CANCELLATION_LOCKED':
        return l10n.t('booking_cancel_blocked_locked');
      default:
        final message = serverMessage?.trim();
        if (message != null && message.isNotEmpty) return message;
        return l10n.t('booking_cancel_failed');
    }
  }

  static String driverAssignmentLabel({
    required AppLocalizations l10n,
    required String status,
    String? driverName,
  }) {
    final name = driverName?.trim();
    if (name != null && name.isNotEmpty) {
      return l10n.t('booking_cancel_driver_assigned').replaceAll('{name}', name);
    }
    if (status == 'DRIVER_ASSIGNED') {
      return l10n.t('booking_cancel_driver_assigned_generic');
    }
    return l10n.t('customer_driver_pending');
  }
}
