import '../../../l10n/app_localizations.dart';

/// Shared booking status labels and customer-facing guidance (Phase 5).
class BookingStatusDisplay {
  BookingStatusDisplay._();

  static String statusLabelKey(String status) {
    switch (status) {
      case 'PENDING':
        return 'status_pending';
      case 'CONFIRMED':
        return 'status_confirmed';
      case 'DRIVER_ASSIGNED':
        return 'status_driver_assigned';
      case 'ON_ROUTE':
        return 'status_on_route';
      case 'DRIVER_ARRIVED':
        return 'status_driver_arrived';
      case 'PICKED_UP':
        return 'status_picked_up';
      case 'COMPLETED':
        return 'status_completed';
      case 'CANCELLED':
        return 'status_cancelled';
      case 'NO_SHOW':
        return 'status_no_show';
      default:
        return 'status';
    }
  }

  static String label(AppLocalizations l10n, String status) {
    return l10n.t(statusLabelKey(status));
  }

  static String? customerGuidanceKey(String status) {
    switch (status) {
      case 'PENDING':
        return 'guest_status_guidance_pending';
      case 'CONFIRMED':
        return 'guest_status_guidance_confirmed';
      case 'DRIVER_ASSIGNED':
        return 'guest_status_guidance_driver_assigned';
      case 'ON_ROUTE':
        return 'guest_status_guidance_on_route';
      case 'DRIVER_ARRIVED':
        return 'guest_status_guidance_driver_arrived';
      case 'PICKED_UP':
        return 'guest_status_guidance_picked_up';
      case 'COMPLETED':
        return 'guest_status_guidance_completed';
      case 'CANCELLED':
        return 'guest_status_guidance_cancelled';
      case 'NO_SHOW':
        return 'guest_status_guidance_no_show';
      default:
        return null;
    }
  }

  static String? customerGuidance(AppLocalizations l10n, String status) {
    final key = customerGuidanceKey(status);
    return key == null ? null : l10n.t(key);
  }
}
