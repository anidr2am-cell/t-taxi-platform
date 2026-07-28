import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
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
  testWidgets('current trip card shows pickup request time and route prefixes', (
    tester,
  ) async {
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
      find.textContaining('고객 픽업 요청 시간 (เวลารับที่ลูกค้าขอ) 7월 29일 22시 23분'),
      findsOneWidget,
    );
    expect(
      find.textContaining('출발지 - Hilton Pattaya(ฮิลตัน พัทยา)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('도착지 - Suvarnabhumi Airport(ท่าอากาศยานสุวรรณภูมิ)'),
      findsOneWidget,
    );
    expect(find.textContaining('지금 할 일'), findsNothing);
    expect(find.textContaining('고객에게 전화'), findsNothing);
    expect(find.text('길찾기 / นำทาง'), findsOneWidget);
  });
}
