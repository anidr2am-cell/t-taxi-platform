import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/utils/location_display.dart';
import 'package:frontend/features/booking/widgets/step_confirmation.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';

void main() {
  late AuthController bookingCompleteAuthController;

  setUp(() async {
    bookingCompleteAuthController = await prepareSignedOutAuthController();
  });

  group('resolveBookingLocationParts', () {
    test('shows name and address when both differ', () {
      final parts = resolveBookingLocationParts(
        name: 'Hilton Pattaya',
        address: '333 Beach Rd, Pattaya, Thailand',
      );
      expect(parts.primaryName, 'Hilton Pattaya');
      expect(parts.secondaryAddress, '333 Beach Rd, Pattaya, Thailand');
    });

    test('shows address only when name is missing', () {
      final parts = resolveBookingLocationParts(address: 'Pattaya Hotel');
      expect(parts.primaryName, isNull);
      expect(parts.secondaryAddress, 'Pattaya Hotel');
    });

    test('shows address only when name equals address', () {
      final parts = resolveBookingLocationParts(
        name: 'Pattaya Hotel',
        address: 'Pattaya Hotel',
      );
      expect(parts.primaryName, isNull);
      expect(parts.secondaryAddress, 'Pattaya Hotel');
    });
  });

  testWidgets('BookingLocationDisplay renders two-line location', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BookingLocationDisplay(
            name: 'BKK — Suvarnabhumi Airport',
            address: '999 Moo 1, Samut Prakan, Thailand',
          ),
        ),
      ),
    );

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(find.text('999 Moo 1, Samut Prakan, Thailand'), findsOneWidget);
  });

  testWidgets('StepConfirmation shows emphasized origin and destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StepConfirmation(
            state: BookingWizardState(
              step: 7,
              origin: testBookingLocation(
                name: 'BKK — Suvarnabhumi Airport',
                address: '999 Moo 1, Samut Prakan, Thailand',
              ),
              destination: testBookingLocation(
                name: 'Hilton Pattaya',
                address: '333 Beach Rd, Pattaya, Thailand',
              ),
              serviceType: BookingServiceType.airportPickup,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(find.text('999 Moo 1, Samut Prakan, Thailand'), findsOneWidget);
    expect(find.text('Hilton Pattaya'), findsOneWidget);
    expect(find.text('333 Beach Rd, Pattaya, Thailand'), findsOneWidget);
  });

  testWidgets('BookingCompletePage shows two-line locations', (tester) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: bookingCompleteAuthController,
        home: BookingCompletePage(
          result: const BookingCreateResult(
            bookingNumber: 'TX202607010001',
            status: 'OPEN',
            paymentMethod: 'PAY_DRIVER',
            paymentStatus: 'UNPAID',
            totalAmount: 1500,
            currency: 'THB',
            boardingQrToken: 'token',
            trustMessage: 'trust',
          ),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(
            name: 'BKK — Suvarnabhumi Airport',
            address: '999 Moo 1, Samut Prakan, Thailand',
          ),
          destination: testBookingLocation(
            name: 'Hilton Pattaya',
            address: '333 Beach Rd, Pattaya, Thailand',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BKK — Suvarnabhumi Airport'), findsWidgets);
    expect(find.text('Hilton Pattaya'), findsWidgets);
  });

  testWidgets('GuestBookingLookupPage shows named lookup locations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          initialResult: GuestBookingLookupResult.fromJson({
            'bookingNumber': 'TX202607010001',
            'status': 'OPEN',
            'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
            'serviceType': {'name': 'Airport Pickup'},
            'route': {
              'origin': {
                'name': 'BKK — Suvarnabhumi Airport',
                'address': '999 Moo 1, Samut Prakan, Thailand',
              },
              'destination': {
                'name': 'Hilton Pattaya',
                'address': '333 Beach Rd, Pattaya, Thailand',
              },
            },
            'pricing': {
              'totalAmount': 1500,
              'currency': 'THB',
              'paymentMethod': 'PAY_DRIVER',
            },
            'guestAccess': {
              'token': 'guest-token',
              'expiresAt': '2099-07-02T00:00:00Z',
            },
            'capabilities': {
              'notificationsAvailable': false,
              'dropoffQrIssueAvailable': false,
              'reviewAvailable': false,
              'trackingAvailable': false,
              'boardingQrRecoverable': true,
              'boardingQrPreviouslyIssued': true,
            },
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(find.text('999 Moo 1, Samut Prakan, Thailand'), findsOneWidget);
    expect(find.text('Hilton Pattaya'), findsOneWidget);
    expect(find.text('333 Beach Rd, Pattaya, Thailand'), findsOneWidget);
  });

  test(
    'GuestBookingLookupResult.fromCreateSummary stores split name and address',
    () {
      final result = GuestBookingLookupResult.fromCreateSummary(
        bookingId: 10,
        bookingNumber: 'TX202607010001',
        status: 'OPEN',
        totalAmount: 1500,
        currency: 'THB',
        paymentMethod: 'PAY_DRIVER',
        guestAccessToken: 'guest-token',
        customerPhone: '+66 81 234 5678',
        serviceTypeName: 'Airport Pickup',
        originName: 'BKK — Suvarnabhumi Airport',
        originAddress: '999 Moo 1, Samut Prakan, Thailand',
        destinationName: 'Hilton Pattaya',
        destinationAddress: '333 Beach Rd, Pattaya, Thailand',
      );

      expect(result.originName, 'BKK — Suvarnabhumi Airport');
      expect(result.originAddress, '999 Moo 1, Samut Prakan, Thailand');
      expect(result.destinationName, 'Hilton Pattaya');
      expect(result.destinationAddress, '333 Beach Rd, Pattaya, Thailand');
    },
  );
}
