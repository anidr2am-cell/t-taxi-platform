import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/firebase/fcm_navigation_service.dart';

void main() {
  test('DRIVER_CALL_AVAILABLE maps to tab 0', () {
    expect(
      tabIndexForNotificationType(driverCallAvailableNotificationType),
      0,
    );
  });

  test('DRIVER_URGENT_CALL_NEW maps to tab 0', () {
    expect(
      tabIndexForNotificationType(driverUrgentCallNewNotificationType),
      0,
    );
  });

  test('ADMIN_RELEASED maps to tab 1', () {
    expect(
      tabIndexForNotificationType(adminReleasedNotificationType),
      1,
    );
  });

  test('SETTLEMENT_APPROVED maps to tab 0', () {
    expect(
      tabIndexForNotificationType(settlementApprovedNotificationType),
      0,
    );
  });

  test('unknown notification types return null', () {
    expect(tabIndexForNotificationType('BOOKING_CONFIRMED'), isNull);
    expect(tabIndexForNotificationType(''), isNull);
    expect(tabIndexForNotificationType(null), isNull);
  });

  test('tabIndexForFcmData reads notificationType from data map', () {
    expect(
      tabIndexForFcmData({'notificationType': 'DRIVER_CALL_AVAILABLE'}),
      0,
    );
    expect(
      tabIndexForFcmData({'notificationType': 'ADMIN_RELEASED'}),
      1,
    );
    expect(
      tabIndexForFcmData({'notificationType': 'SETTLEMENT_APPROVED'}),
      0,
    );
    expect(tabIndexForFcmData({'notificationType': 'UNKNOWN'}), isNull);
    expect(tabIndexForFcmData(const {}), isNull);
  });
}
