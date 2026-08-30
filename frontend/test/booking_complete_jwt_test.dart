import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/widgets/booking_notification_section.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/features/booking/widgets/guest_booking_cancel_section.dart';
import 'package:frontend/features/driver_location/widgets/guest_driver_tracking_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';

BookingCreateResult _loggedInCreateResult({
  String status = 'DRIVER_ASSIGNED',
  bool trackingAvailable = true,
  String? guestAccessToken,
}) {
  return BookingCreateResult(
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    status: status,
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: guestAccessToken,
    boardingQrToken: 'boarding-token',
    trustMessage: 'Booking received',
    trackingAvailable: trackingAvailable,
    canCancel: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AuthTokenStorage.accessTokenKey: 'customer-jwt',
      AuthTokenStorage.refreshTokenKey: 'refresh-token',
      AuthTokenStorage.userJsonKey: jsonEncode({
        'id': 42,
        'email': 'guest@example.com',
        'role': 'CUSTOMER',
        'name': 'Minji',
        'phone': null,
        'locale': 'ko',
        'isActive': true,
      }),
    });
  });

  testWidgets('booking complete shows tracking without guest token when JWT loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          result: _loggedInCreateResult(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          enableCustomerTools: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GuestDriverTrackingSection), findsOneWidget);
    final section = tester.widget<GuestDriverTrackingSection>(
      find.byType(GuestDriverTrackingSection),
    );
    expect(section.guestAccessToken, isEmpty);
    expect(section.useCustomerAuth, isTrue);
    expect(section.customerAccessToken, 'customer-jwt');
  });

  testWidgets('booking complete hides customer tools until JWT loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          result: _loggedInCreateResult(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          enableCustomerTools: true,
          tokenStorage: DelayedAuthTokenStorage(
            const Duration(milliseconds: 200),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GuestDriverTrackingSection), findsNothing);
    expect(find.byType(GuestBookingCancelSection), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GuestDriverTrackingSection), findsOneWidget);
    expect(find.byType(GuestBookingCancelSection), findsOneWidget);
  });

  testWidgets('booking complete completed trip shows notifications and review with JWT', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          result: _loggedInCreateResult(status: 'COMPLETED'),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          enableCustomerTools: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BookingNotificationSection), findsOneWidget);
    final notifications = tester.widget<BookingNotificationSection>(
      find.byType(BookingNotificationSection),
    );
    expect(notifications.customerAccessToken, 'customer-jwt');
    expect(notifications.useCustomerPushRegistration, isTrue);

    expect(find.byType(BookingReviewForm), findsOneWidget);
    final review = tester.widget<BookingReviewForm>(
      find.byType(BookingReviewForm),
    );
    expect(review.customerAccessToken, 'customer-jwt');
  });

  testWidgets('booking complete still prefers guest token when both are present', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: createSignedOutAuthController(),
        locale: const Locale('en'),
        includeAppLocalizations: true,
        home: BookingCompletePage(
          result: _loggedInCreateResult(guestAccessToken: 'guest-token'),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          enableCustomerTools: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final section = tester.widget<GuestDriverTrackingSection>(
      find.byType(GuestDriverTrackingSection),
    );
    expect(section.guestAccessToken, 'guest-token');
    expect(section.customerAccessToken, 'customer-jwt');
    expect(section.useCustomerAuth, isTrue);
  });
}
