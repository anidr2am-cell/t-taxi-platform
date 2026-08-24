import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/booking/models/booking_complete_review.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';

late AuthController _authController;

void main() {
  setUp(() async {
    _authController = await prepareSignedOutAuthController();
  });

  testWidgets(
    'customer tools enabled before assignment keeps removed contact entry hidden',
    (tester) async {
      await tester.pumpWidget(_wrap(_page()));

      expect(find.text('Boarding QR'), findsNothing);
      expect(find.text('Ride completion QR'), findsNothing);
      expect(find.text('Refresh dropoff QR'), findsNothing);
      expect(find.text('Issue new dropoff QR'), findsNothing);
    },
  );

  testWidgets(
    'customer tools keep removed contact entry hidden after assignment',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_page(result: _result(status: 'ON_ROUTE'))),
      );

      expect(find.text('Boarding QR'), findsNothing);
      expect(find.text('Ride completion QR'), findsNothing);
    },
  );

  testWidgets('completed state shows completion message without QR', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'COMPLETED'))));

    expect(find.text('Trip completed'), findsOneWidget);
    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('Ride completion QR'), findsNothing);
  });

  testWidgets('completed booking with token and no review shows review form', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'COMPLETED'))));

    expect(find.text('Trip completed'), findsOneWidget);
    expect(find.text('How was your ride?'), findsOneWidget);
    expect(find.text('Submit rating'), findsOneWidget);
  });

  testWidgets('completed booking with existing review hides submit form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _page(
          result: _result(status: 'COMPLETED'),
          review: const BookingCompleteReview(
            customerName: 'Kim',
            customerPhone: '+66123456789',
          ),
        ),
      ),
    );

    expect(find.text('Kim'), findsOneWidget);
    expect(find.text('How was your ride?'), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets(
    'completed booking without notification still shows review form',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_page(result: _result(status: 'COMPLETED', bookingId: null))),
      );

      expect(find.text('Trip completed'), findsOneWidget);
      expect(find.text('How was your ride?'), findsOneWidget);
    },
  );

  testWidgets('in-progress booking does not show review form', (tester) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'PICKED_UP'))));

    expect(find.text('How was your ride?'), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
  });
}

Widget _wrap(Widget child) {
  return wrapBookingCompleteTestApp(home: child, authController: _authController);
}

BookingCompletePage _page({
  BookingCreateResult? result,
  BookingCompleteReview? review,
}) {
  return BookingCompletePage(
    result: result ?? _result(),
    serviceLabel: 'Airport Pickup',
    origin: testBookingLocation(name: 'BKK Airport', address: 'BKK Airport'),
    destination: testBookingLocation(
      name: 'Pattaya Hotel',
      address: 'Pattaya Hotel',
    ),
    review: review,
    enableCustomerTools: true,
  );
}

BookingCreateResult _result({String status = 'PENDING', int? bookingId = 1}) {
  return BookingCreateResult(
    bookingId: bookingId,
    bookingNumber: 'TX202607010001',
    status: status,
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    boardingQrToken: 'boarding-token',
    trustMessage: 'Booking received',
  );
}
