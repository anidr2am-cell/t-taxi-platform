import '../../../l10n/app_localizations.dart';

class AdminBookingView {
  static const needsAction = 'needs_action';
  static const issues = 'issues';
  static const today = 'today';
  static const upcoming = 'upcoming';
  static const inProgress = 'in_progress';
  static const settlement = 'settlement';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const all = 'all';

  static const ordered = [
    needsAction,
    today,
    upcoming,
    inProgress,
    settlement,
    completed,
    cancelled,
    all,
  ];
}

class AdminOperationsUx {
  static String viewLabel(AppLocalizations l10n, String view) {
    switch (view) {
      case AdminBookingView.needsAction:
        return l10n.t('admin_ops_view_needs_action');
      case AdminBookingView.today:
        return l10n.t('admin_ops_view_today');
      case AdminBookingView.upcoming:
        return l10n.t('admin_ops_view_upcoming');
      case AdminBookingView.inProgress:
        return l10n.t('admin_ops_view_in_progress');
      case AdminBookingView.settlement:
        return l10n.t('admin_ops_view_settlement');
      case AdminBookingView.completed:
        return l10n.t('admin_ops_view_completed');
      case AdminBookingView.cancelled:
        return l10n.t('admin_ops_view_cancelled');
      case AdminBookingView.all:
        return l10n.t('admin_ops_view_all');
      default:
        return view;
    }
  }

  static String summaryCardLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'needsAction':
        return l10n.t('admin_ops_summary_needs_action');
      case 'unassigned':
        return l10n.t('admin_ops_summary_unassigned');
      case 'today':
        return l10n.t('admin_ops_summary_today');
      case 'inProgress':
        return l10n.t('admin_ops_summary_in_progress');
      case 'settlementPending':
        return l10n.t('admin_ops_summary_settlement');
      case 'issues':
        return l10n.t('admin_ops_summary_issues');
      default:
        return key;
    }
  }

  static String? viewForSummaryCard(String key) {
    switch (key) {
      case 'needsAction':
        return AdminBookingView.needsAction;
      case 'unassigned':
        return AdminBookingView.all;
      case 'today':
        return AdminBookingView.today;
      case 'inProgress':
        return AdminBookingView.inProgress;
      case 'settlementPending':
        return AdminBookingView.settlement;
      case 'issues':
        return AdminBookingView.issues;
      default:
        return null;
    }
  }

  static String severityLabel(AppLocalizations l10n, String? severity) {
    switch (severity) {
      case 'URGENT':
        return l10n.t('admin_ops_severity_urgent');
      case 'SOON':
        return l10n.t('admin_ops_severity_soon');
      case 'REVIEW':
        return l10n.t('admin_ops_severity_review');
      default:
        return '';
    }
  }

  static String actionReasonLabel(AppLocalizations l10n, String? code) {
    switch (code) {
      case 'LOW_RATING':
        return l10n.t('admin_ops_reason_low_rating');
      case 'RECEIPT_REJECTED':
        return l10n.t('admin_ops_reason_receipt_rejected');
      case 'RECEIPT_REVIEW':
        return l10n.t('admin_ops_reason_receipt_review');
      case 'RECEIPT_MISSING':
        return l10n.t('admin_ops_reason_receipt_missing');
      case 'PICKUP_OVERDUE_UNASSIGNED':
        return l10n.t('admin_ops_reason_pickup_overdue_unassigned');
      case 'PICKUP_OVERDUE_STALLED':
        return l10n.t('admin_ops_reason_pickup_overdue_stalled');
      case 'PICKUP_SOON_UNASSIGNED':
        return l10n.t('admin_ops_reason_pickup_soon_unassigned');
      case 'CUSTOMER_INQUIRY':
        return l10n.t('admin_ops_reason_customer_inquiry');
      case 'BOARDING_DELAY':
        return l10n.t('admin_ops_reason_boarding_delay');
      case 'LONG_TRIP':
        return l10n.t('admin_ops_reason_long_trip');
      case 'STATUS_STALE':
        return l10n.t('admin_ops_reason_status_stale');
      default:
        return '';
    }
  }

  static String formatActionReason(
    AppLocalizations l10n,
    Map<String, dynamic>? operations,
  ) {
    if (operations == null) return '';
    final primary = operations['primaryActionReason'] as String?;
    if (primary == null || primary.isEmpty) return '';
    return actionReasonLabel(l10n, primary);
  }

  static List<String> secondaryActionReasonLabels(
    AppLocalizations l10n,
    Map<String, dynamic>? operations,
  ) {
    final reasons = operations?['actionReasons'];
    if (reasons is! List || reasons.length <= 1) return const [];
    return reasons
        .skip(1)
        .map((code) => actionReasonLabel(l10n, code?.toString()))
        .where((label) => label.isNotEmpty)
        .toList();
  }

  static String nextActionLabel(
    AppLocalizations l10n,
    Map<String, dynamic>? operations,
    Map<String, dynamic>? detail,
  ) {
    final next = operations?['nextAction'];
    final code = next is Map ? next['code'] as String? : null;
    switch (code) {
      case 'LOW_RATING':
        return l10n.t('admin_ops_next_low_rating');
      case 'RECEIPT_REJECTED':
      case 'RECEIPT_REVIEW':
        return l10n.t('admin_ops_next_receipt_review');
      case 'RECEIPT_MISSING':
      case 'AWAIT_RECEIPT':
        return l10n.t('admin_ops_next_receipt_missing');
      case 'PICKUP_OVERDUE_UNASSIGNED':
      case 'PICKUP_SOON_UNASSIGNED':
        return l10n.t('admin_ops_next_assign_driver');
      case 'CUSTOMER_INQUIRY':
        return l10n.t('admin_ops_next_customer_inquiry');
      case 'BOARDING_DELAY':
        return l10n.t('admin_ops_next_boarding_delay');
      case 'LONG_TRIP':
        return l10n.t('admin_ops_next_long_trip');
      case 'ASSIGN_DRIVER':
        return l10n.t('admin_dispatch_next_action_assign');
      case 'CONFIRM_SETTLEMENT':
        return l10n.t('admin_ops_next_confirm_settlement');
      default:
        if (detail?['status'] == 'SETTLEMENT_PENDING') {
          return l10n.t('admin_ops_next_receipt_missing');
        }
        return l10n.t('admin_dispatch_next_action_none');
    }
  }

  static String primaryCtaLabel(AppLocalizations l10n, String? cta) {
    switch (cta) {
      case 'ASSIGN_DRIVER':
        return l10n.t('admin_dispatch_assign_driver');
      case 'CONFIRM_SETTLEMENT':
        return l10n.t('admin_settlement_confirm_200');
      case 'SETTLEMENT_DETAIL':
        return l10n.t('admin_ops_cta_settlement_detail');
      case 'REVIEW_RATING':
        return l10n.t('admin_ops_cta_review_rating');
      case 'OPEN_CHAT':
        return l10n.t('admin_ops_cta_open_chat');
      case 'CHECK_STATUS':
        return l10n.t('admin_ops_cta_check_status');
      default:
        return l10n.t('admin_ops_cta_view_booking');
    }
  }

  static String listCtaLabel(AppLocalizations l10n) {
    return l10n.t('admin_ops_cta_review_act');
  }

  static String routeContextLabel(
    AppLocalizations l10n,
    String? serviceTypeCode,
  ) {
    switch (serviceTypeCode?.toUpperCase()) {
      case 'AIRPORT_PICKUP':
      case 'AIRPORT_TO_CITY':
        return l10n.t('admin_ops_route_airport_pickup');
      case 'AIRPORT_DROPOFF':
      case 'CITY_TO_AIRPORT':
        return l10n.t('admin_ops_route_airport_dropoff');
      case 'CITY_TRANSFER':
      default:
        return l10n.t('admin_ops_route_city_transfer');
    }
  }
}
