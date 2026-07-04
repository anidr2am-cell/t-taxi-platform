import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';

void main() {
  testWidgets('booking complete hides QR and chat by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookingCompletePage(
          result: _result(),
          serviceLabel: 'Airport Pickup',
          originLabel: 'BKK Airport',
          destinationLabel: 'Pattaya',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TX202607010001'), findsOneWidget);
    expect(find.text('Track my booking'), findsOneWidget);
    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('chat_after_driver_assignment'), findsNothing);
  });
}

BookingCreateResult _result() {
  return const BookingCreateResult(
    bookingNumber: 'TX202607010001',
    status: 'PENDING',
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    chatRoomCode: 'CHAT-TX202607010001',
    boardingQrToken: 'boarding-token',
    trustMessage: 'Booking received',
  );
}
