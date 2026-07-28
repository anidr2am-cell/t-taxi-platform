import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/presentation/booking_display_formatters.dart';

void main() {
  group('formatBookingLocation', () {
    test('prefers nameTh over name for the primary line', () {
      expect(
        formatBookingLocation(
          const BookingLocation(
            name: 'BKK — Suvarnabhumi Airport',
            nameTh: 'ท่าอากาศยานสุวรรณภูมิ',
            address: '999 Nong Prue, Bang Phli',
          ),
        ),
        'ท่าอากาศยานสุวรรณภูมิ\n999 Nong Prue, Bang Phli',
      );
    });

    test('falls back to name when nameTh is absent', () {
      expect(
        formatBookingLocation(
          const BookingLocation(
            name: 'Hilton Pattaya',
            address: '333 Moo 9, Pattaya Beach Road',
          ),
        ),
        'Hilton Pattaya\n333 Moo 9, Pattaya Beach Road',
      );
    });

    test('shows address only when neither nameTh nor name is available', () {
      expect(
        formatBookingLocation(
          const BookingLocation(address: '999 Nong Prue, Bang Phli'),
        ),
        '999 Nong Prue, Bang Phli',
      );
    });

    test('returns placeholder when all location labels are missing', () {
      expect(formatBookingLocation(const BookingLocation()), '위치 정보 없음');
    });
  });

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
