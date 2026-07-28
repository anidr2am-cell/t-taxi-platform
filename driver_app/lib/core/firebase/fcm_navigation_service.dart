const driverCallAvailableNotificationType = 'DRIVER_CALL_AVAILABLE';
const driverUrgentCallNewNotificationType = 'DRIVER_URGENT_CALL_NEW';
const adminReleasedNotificationType = 'ADMIN_RELEASED';

/// Maps FCM [notificationType] values to driver home shell tab indices.
///
/// Tab 0 is always "새 콜" and tab 1 is always "내 운행".
int? tabIndexForNotificationType(String? notificationType) {
  switch (notificationType) {
    case driverCallAvailableNotificationType:
    case driverUrgentCallNewNotificationType:
      return 0;
    case adminReleasedNotificationType:
      return 1;
    default:
      return null;
  }
}

int? tabIndexForFcmData(Map<String, dynamic> data) {
  final raw = data['notificationType'];
  return tabIndexForNotificationType(raw is String ? raw : null);
}
