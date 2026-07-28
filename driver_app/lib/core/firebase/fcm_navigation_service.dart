const driverCallAvailableNotificationType = 'DRIVER_CALL_AVAILABLE';
const driverUrgentCallNewNotificationType = 'DRIVER_URGENT_CALL_NEW';
const adminReleasedNotificationType = 'ADMIN_RELEASED';
const settlementApprovedNotificationType = 'SETTLEMENT_APPROVED';

/// Maps FCM [notificationType] values to driver home shell tab indices.
///
/// Tab 0 is always "새 콜" and tab 1 is always "내 운행".
int? tabIndexForNotificationType(String? notificationType) {
  switch (notificationType) {
    case driverCallAvailableNotificationType:
    case driverUrgentCallNewNotificationType:
    case settlementApprovedNotificationType:
      return 0;
    case adminReleasedNotificationType:
      return 1;
    default:
      return null;
  }
}

/// Settlement approval has no Socket.IO fallback, so foreground FCM should
/// refresh the open-calls tab the same way background tap navigation does.
bool shouldHandleSettlementApprovedInForeground(Map<String, dynamic> data) {
  final raw = data['notificationType'];
  return raw is String && raw == settlementApprovedNotificationType;
}

int? tabIndexForFcmData(Map<String, dynamic> data) {
  final raw = data['notificationType'];
  return tabIndexForNotificationType(raw is String ? raw : null);
}
