import '../../../l10n/app_localizations.dart';

/// Audience for role-specific booking status copy.
enum BookingStatusAudience { customer, driver, admin }

/// Shared booking status labels and customer-facing guidance (Phase 5).
class BookingStatusDisplay {
  BookingStatusDisplay._();

  static String statusLabelKey(
    String status, {
    BookingStatusAudience audience = BookingStatusAudience.customer,
  }) {
    if (status == 'SETTLEMENT_PENDING') {
      return switch (audience) {
        BookingStatusAudience.customer => 'status_customer_settlement_pending',
        BookingStatusAudience.driver => 'status_driver_settlement_pending',
        BookingStatusAudience.admin => 'status_admin_settlement_pending',
      };
    }

    switch (status) {
      case 'PENDING':
        return 'status_pending';
      case 'OPEN':
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

  static String label(
    AppLocalizations l10n,
    String status, {
    BookingStatusAudience audience = BookingStatusAudience.customer,
    bool reassignmentInProgress = false,
  }) {
    if (reassignmentInProgress &&
        (status == 'OPEN' || status == 'PENDING' || status == 'CONFIRMED')) {
      return l10n.t('status_reassignment_in_progress');
    }
    return l10n.t(statusLabelKey(status, audience: audience));
  }

  static String? customerGuidanceKey(
    String status, {
    bool reassignmentInProgress = false,
  }) {
    if (reassignmentInProgress &&
        (status == 'OPEN' || status == 'PENDING' || status == 'CONFIRMED')) {
      return 'guest_status_guidance_reassignment';
    }
    switch (status) {
      case 'PENDING':
        return 'guest_status_guidance_pending';
      case 'OPEN':
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
      case 'SETTLEMENT_PENDING':
        return 'guest_status_guidance_settlement_pending';
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

  static String? customerGuidance(
    AppLocalizations l10n,
    String status, {
    bool reassignmentInProgress = false,
  }) {
    final key = customerGuidanceKey(
      status,
      reassignmentInProgress: reassignmentInProgress,
    );
    return key == null ? null : l10n.t(key);
  }
}
