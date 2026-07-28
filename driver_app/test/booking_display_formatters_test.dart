import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/presentation/booking_display_formatters.dart';
import 'package:tride_driver/l10n/app_localizations.dart';

void main() {
  final koL10n = AppLocalizations(const Locale('ko'));

  group('formatBookingLocation', () {
    test('prefers nameTh over name for the primary line', () {
      expect(
        formatBookingLocation(
          koL10n,
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
          koL10n,
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
          koL10n,
          const BookingLocation(address: '999 Nong Prue, Bang Phli'),
        ),
        '999 Nong Prue, Bang Phli',
      );
    });

    test('returns placeholder when all location labels are missing', () {
      expect(
        formatBookingLocation(koL10n, const BookingLocation()),
        koL10n.noLocationInfo,
      );
    });
  });

  group('formatBookingCreatedAtLabel', () {
    test('formats ISO UTC timestamps in Bangkok wall clock', () {
      expect(
        formatBookingCreatedAtLabel(koL10n, '2026-07-12T08:30:00.000Z'),
        '예약: 7월 12일 15시 30분',
      );
    });

    test('returns null when createdAt is missing', () {
      expect(formatBookingCreatedAtLabel(koL10n, null), isNull);
      expect(formatBookingCreatedAtLabel(koL10n, ''), isNull);
    });
  });

  group('parseBookingLocation', () {
    test('splits place name and address lines', () {
      final lines = parseBookingLocation(
        const BookingLocation(
          name: 'Hilton Pattaya',
          address: '333 Moo 9, Pattaya Beach Road',
        ),
      );
      expect(lines.placeName, 'Hilton Pattaya');
      expect(lines.addressLine, '333 Moo 9, Pattaya Beach Road');
      expect(lines.hasSeparateAddress, isTrue);
    });

    test('returns address only when names are missing', () {
      final lines = parseBookingLocation(
        const BookingLocation(address: '999 Nong Prue, Bang Phli'),
      );
      expect(lines.placeName, isNull);
      expect(lines.addressLine, '999 Nong Prue, Bang Phli');
      expect(lines.hasSeparateAddress, isFalse);
    });
  });

  group('assignmentReleasedCloseMessage', () {
    test('shows admin message for ADMIN_RELEASED', () {
      expect(
        assignmentReleasedCloseMessage(
          koL10n,
          const {'reasonCode': 'ADMIN_RELEASED'},
        ),
        koL10n.assignmentReleasedAdminMessage,
      );
    });

    test('shows default message for DRIVER_RELEASED', () {
      expect(
        assignmentReleasedCloseMessage(
          koL10n,
          const {'reasonCode': 'DRIVER_RELEASED'},
        ),
        koL10n.assignmentReleasedDefaultMessage,
      );
    });

    test('shows default message when reasonCode is missing', () {
      expect(
        assignmentReleasedCloseMessage(koL10n, const {}),
        koL10n.assignmentReleasedDefaultMessage,
      );
    });
  });
}
