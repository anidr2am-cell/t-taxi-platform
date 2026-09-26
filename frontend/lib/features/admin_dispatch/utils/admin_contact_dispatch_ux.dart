class AdminContactDispatchUx {
  const AdminContactDispatchUx._();

  static String contactStatusLabelKey(String? status) {
    switch (status) {
      case 'PENDING':
        return 'admin_contact_status_pending';
      case 'CONFIRM_REQUESTED':
        return 'admin_contact_status_confirm_requested';
      case 'VERIFIED':
        return 'admin_contact_status_verified';
      default:
        return 'admin_contact_status_verified';
    }
  }

  static String dispatchStateLabelKey(String? state) {
    switch (state) {
      case 'WAITING_CONTACT':
        return 'admin_contact_dispatch_state_waiting_contact';
      case 'DISPATCH_PENDING':
        return 'admin_contact_dispatch_state_dispatch_pending';
      case 'DELIVERY_RETRY_NEEDED':
        return 'admin_contact_dispatch_state_delivery_retry_needed';
      case 'DELIVERY_ATTEMPTED':
        return 'admin_contact_dispatch_state_delivery_attempted';
      case 'NOT_OPEN':
        return 'admin_contact_dispatch_state_not_open';
      case 'NOT_APPLICABLE':
      default:
        return 'admin_contact_dispatch_state_not_applicable';
    }
  }

  static String dispatchModeLabelKey(String? mode) {
    return mode == 'URGENT'
        ? 'admin_contact_dispatch_mode_urgent'
        : 'admin_contact_dispatch_mode_standard';
  }

  static String? retryErrorLabelKey(String? errorCode) {
    switch (errorCode) {
      case 'CONTACT_DISPATCH_IN_PROGRESS':
        return 'admin_contact_dispatch_error_in_progress';
      case 'CONTACT_DISPATCH_ALREADY_DELIVERED':
        return 'admin_contact_dispatch_error_already_delivered';
      case 'CONTACT_DISPATCH_NOT_RETRYABLE':
        return 'admin_contact_dispatch_error_not_retryable';
      default:
        return null;
    }
  }

  static bool showVerifyCta({
    required String? contactStatus,
    required List<String> allowedActions,
  }) {
    return contactStatus == 'CONFIRM_REQUESTED' &&
        allowedActions.contains('VERIFY_CONTACT');
  }

  static bool showRetryCta({
    required bool retryable,
    required List<String> allowedActions,
    required String? state,
  }) {
    if (!retryable || !allowedActions.contains('RETRY_CONTACT_DISPATCH')) {
      return false;
    }
    return state == 'DISPATCH_PENDING' || state == 'DELIVERY_RETRY_NEEDED';
  }
}
