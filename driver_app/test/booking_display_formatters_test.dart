import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/bookings/presentation/booking_display_formatters.dart';

void main() {
  group('assignmentReleasedCloseMessage', () {
    test('shows admin message for ADMIN_RELEASED', () {
      expect(
        assignmentReleasedCloseMessage(const {'reasonCode': 'ADMIN_RELEASED'}),
        assignmentReleasedAdminCloseMessage,
      );
    });

    test('shows default message for DRIVER_RELEASED', () {
      expect(
        assignmentReleasedCloseMessage(const {'reasonCode': 'DRIVER_RELEASED'}),
        assignmentReleasedDefaultCloseMessage,
      );
    });

    test('shows default message when reasonCode is missing', () {
      expect(
        assignmentReleasedCloseMessage(const {}),
        assignmentReleasedDefaultCloseMessage,
      );
    });
  });
}
