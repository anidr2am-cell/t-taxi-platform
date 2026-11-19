import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/driver/widgets/driver_today_trip_cards.dart';

DriverBooking _cardBooking({
  DriverBookingLocation? pickupLocation,
  DriverBookingLocation? destinationLocation,
}) {
  return DriverBooking(
    bookingNumber: 'TX202607010001',
    status: 'DRIVER_ASSIGNED',
    serviceTypeName: 'Airport Pickup',
    pickupDate: '2026-07-29',
    pickupTime: '22:23',
    origin: 'BKK Airport',
    destination: 'Pattaya Hotel',
    passengerCount: 2,
    vehicleTypeName: 'SUV',
    customerDisplayName: 'Kim',
    allowedActions: const ['VIEW_DETAILS'],
    pickupLocation: pickupLocation,
    destinationLocation: destinationLocation,
  );
}

void main() {
  test('critical driver confirmations and settlement notices include Thai', () {
    final l10n = AppLocalizations('th');
    for (final key in [
      'driver_account_terms_placeholder',
      'driver_account_privacy_placeholder',
      'driver_confirm_start_on_route_title',
      'driver_confirm_start_on_route_message',
      'driver_confirm_accept_booking_title',
      'driver_confirm_accept_booking_message',
      'driver_confirm_mark_arrived_title',
      'driver_confirm_mark_arrived_message',
      'driver_confirm_mark_picked_up_title',
      'driver_confirm_mark_picked_up_message',
      'driver_confirm_end_trip_title',
      'driver_confirm_end_trip_message',
      'driver_success_picked_up',
      'driver_success_end_trip',
      'driver_trip_settlement_pending_info',
      'driver_trip_completed_info',
      'driver_settlement_popup_title',
      'driver_settlement_popup_message',
    ]) {
      expect(
        RegExp(r'[\u0E00-\u0E7F]').hasMatch(l10n.t(key)),
        isTrue,
        reason: key,
      );
    }
  });

  testWidgets(
    'current trip card shows pickup request time and route prefixes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverTodayCurrentTripCard(
              booking: _cardBooking(
                pickupLocation: const DriverBookingLocation(
                  name: 'Hilton Pattaya',
                  nameTh: 'ฮิลตัน พัทยา',
                ),
                destinationLocation: const DriverBookingLocation(
                  name: 'Suvarnabhumi Airport',
                  nameTh: 'ท่าอากาศยานสุวรรณภูมิ',
                ),
              ),
              onOpenPrimary: () {},
            ),
          ),
        ),
      );

      expect(
        find.textContaining(
          'เวลารับที่ลูกค้าขอ / 고객 픽업 요청 시간 29/07/2026 22:23 (เวลาไทย / 태국 시간)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('จุดรับ / 출발지 -'), findsOneWidget);
      expect(find.textContaining('ฮิลตัน พัทยา'), findsOneWidget);
      expect(find.textContaining('จุดส่ง / 도착지 -'), findsOneWidget);
      expect(find.textContaining('ท่าอากาศยานสุวรรณภูมิ'), findsOneWidget);
      expect(find.textContaining('지금 할 일'), findsNothing);
      expect(find.textContaining('고객에게 전화'), findsNothing);
      expect(find.text('길찾기 / นำทาง'), findsOneWidget);
    },
  );
}
