import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('booking complete trust copy is QR-free in every customer locale', () {
    for (final languageCode in AppLocalizations.supportedLanguages) {
      final message = AppLocalizations(
        languageCode,
      ).t('booking_trust_message');
      expect(message.toLowerCase(), isNot(contains('qr')), reason: languageCode);
    }
  });

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
    expect(find.textContaining('QR'), findsNothing);
    expect(find.text('chat_after_driver_assignment'), findsNothing);
  });

  testWidgets('booking complete ignores a backend QR trust-message fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookingCompletePage(
          result: _result(trustMessage: 'Show the boarding QR to the driver.'),
          serviceLabel: 'Airport Pickup',
          originLabel: 'BKK Airport',
          destinationLabel: 'Pattaya',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Keep your booking number. You can check driver assignment and trip status on the booking lookup page.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('QR'), findsNothing);
  });
}

BookingCreateResult _result({String trustMessage = 'Booking received'}) {
  return BookingCreateResult(
    bookingNumber: 'TX202607010001',
    status: 'PENDING',
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    chatRoomCode: 'CHAT-TX202607010001',
    boardingQrToken: 'boarding-token',
    trustMessage: trustMessage,
  );
}
