import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:frontend/features/booking/widgets/airport_meeting_guide_card.dart';
import 'package:frontend/theme/app_tokens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

late AuthController _bookingCompleteAuthController;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _bookingCompleteAuthController = await prepareSignedOutAuthController();
  });

  testWidgets('BKK airport pickup without name sign shows Gate 7 guide', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AirportMeetingGuideCard(
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
        ),
      ),
    );

    expect(find.text('Vehicle pickup guide · Gate 7'), findsOneWidget);
    expect(find.text('Name sign meeting guide · Gate 3'), findsNothing);
    expect(
      find.textContaining('Driver and vehicle details are pending'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Pickup notification becomes available after a driver is assigned.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('BKK airport pickup with name sign shows Gate 3 guide', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AirportMeetingGuideCard(
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: true,
        ),
      ),
    );

    expect(find.text('Name sign meeting guide · Gate 3'), findsOneWidget);
    expect(find.text('Vehicle pickup guide · Gate 7'), findsNothing);
    expect(find.textContaining('Do not go outside'), findsOneWidget);
  });

  testWidgets('airport dropoff and other airports hide the BKK guide', (
    tester,
  ) async {
    expect(
      AirportMeetingGuideCard.shouldShow(
        serviceTypeCode: 'AIRPORT_DROPOFF',
        originAirportCode: 'BKK',
      ),
      isFalse,
    );
    expect(
      AirportMeetingGuideCard.shouldShow(
        serviceTypeCode: 'AIRPORT_PICKUP',
        originAirportCode: 'DMK',
      ),
      isFalse,
    );
  });

  testWidgets('assigned vehicle and driver details are displayed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AirportMeetingGuideCard(
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
          vehicleInfo: AirportMeetingVehicleInfo(
            driverName: 'Driver A',
            driverPhone: '+66 80 000 0000',
            vehicleType: 'SUV',
            vehicleColor: 'Black',
            vehiclePlateNumber: '1錫곟툊1234',
          ),
        ),
      ),
    );

    expect(find.text('Driver A'), findsOneWidget);
    expect(find.text('+66 80 000 0000'), findsOneWidget);
    expect(find.text('SUV'), findsOneWidget);
    expect(find.text('Black'), findsOneWidget);
    expect(find.text('1錫곟툊1234'), findsOneWidget);
  });

  testWidgets('pickup notification action is enabled and sends once', (
    tester,
  ) async {
    var sends = 0;
    await tester.pumpWidget(
      _wrap(
        AirportMeetingGuideCard(
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
          onNotifyPickup: () async {
            sends += 1;
          },
        ),
      ),
    );

    expect(
      find.text(
        'After arrival and collecting your luggage, notify your driver.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Tell driver I’m ready'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Tell driver I’m ready'));
    await tester.pumpAndSettle();
    expect(find.text('Tell driver I’m ready'), findsWidgets);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(sends, 1);
    expect(find.text('Pickup notification sent'), findsOneWidget);
    await tester.tap(find.text('Pickup notification sent'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(sends, 1);
  });

  testWidgets('Gate 7 step 2 shows Korean warning text in error color', (
    tester,
  ) async {
    const warning = '기사에게 픽업 알림을 보냅니다. 꼭 수하물을 찾으신 후에 알림을 보내주시기 바랍니다';
    await tester.pumpWidget(
      _wrap(
        const AirportMeetingGuideCard(
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
        ),
        locale: const Locale('ko'),
      ),
    );

    final warningText = tester.widget<Text>(find.text(warning));
    expect(warningText.style?.color, AppTokens.error);
  });

  testWidgets('guest lookup hides removed contact and pickup alert actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        GuestBookingLookupPage(
          lookupService: _FakeLookupService(_lookupResult(nameSign: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tell driver I’m ready'), findsNothing);
  });

  testWidgets('guest lookup does not expose removed pickup alert flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        GuestBookingLookupPage(
          lookupService: _FakeLookupService(_lookupResult(nameSign: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tell driver I’m ready'), findsNothing);
  });

  testWidgets('lookup keeps pickup alert disabled in active pickup statuses', (
    tester,
  ) async {
    for (final status in ['DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED']) {
      await tester.pumpWidget(
        _wrapPage(
          GuestBookingLookupPage(
            lookupService: _FakeLookupService(
              _lookupResult(nameSign: false, status: status),
            ),
            enableCustomerTools: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tell driver I’m ready'), findsNothing, reason: status);
    }
  });

  testWidgets(
    'lookup disables pickup alert before assignment and when terminal',
    (tester) async {
      for (final status in ['PENDING', 'COMPLETED', 'CANCELLED']) {
        await tester.pumpWidget(
          _wrapPage(
            GuestBookingLookupPage(
              lookupService: _FakeLookupService(
                _lookupResult(
                  nameSign: false,
                  status: status,
                  includeDriver: status != 'PENDING',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Pickup notification becomes available after a driver is assigned.',
          ),
          findsOneWidget,
          reason: status,
        );
        expect(find.text('Tell driver I’m ready'), findsNothing);
      }
    },
  );

  testWidgets('booking complete screen displays BKK meeting guide', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        BookingCompletePage(
          result: _bookingResult(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Vehicle pickup guide · Gate 7'), findsOneWidget);
    expect(find.text('Boarding QR'), findsNothing);
  });

  testWidgets('booking complete hides removed customer contact entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        BookingCompletePage(
          result: _bookingResult(status: 'DRIVER_ASSIGNED'),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
          meetingVehicleInfo: const AirportMeetingVehicleInfo(
            driverName: 'Driver A',
            vehiclePlateNumber: '1ABC1234',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('booking complete screen hides QR when customer tools enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        BookingCompletePage(
          result: _bookingResult(),
          serviceLabel: 'Airport Pickup',
          origin: testBookingLocation(name: 'BKK Airport'),
          destination: testBookingLocation(name: 'Pattaya'),
          serviceTypeCode: 'AIRPORT_PICKUP',
          originAirportCode: 'BKK',
          nameSignRequested: false,
          enableCustomerTools: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Boarding QR'), findsNothing);
  });

  testWidgets('guest lookup screen displays BKK name sign meeting guide', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        GuestBookingLookupPage(
          lookupService: _FakeLookupService(_lookupResult(nameSign: true)),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name sign meeting guide · Gate 3'), findsOneWidget);
    expect(find.text('Vehicle pickup guide · Gate 7'), findsNothing);
  });

  testWidgets('guest lookup screen displays Gate 7 when name sign is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        GuestBookingLookupPage(
          lookupService: _FakeLookupService(_lookupResult(nameSign: false)),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Gate 7'), findsWidgets);
    expect(find.textContaining('Gate 3'), findsNothing);
  });

  testWidgets('guest lookup screen hides BKK guide for another airport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        GuestBookingLookupPage(
          lookupService: _FakeLookupService(
            _lookupResult(nameSign: false, originCode: 'DMK'),
          ),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Gate 7'), findsNothing);
    expect(find.textContaining('Gate 3'), findsNothing);
  });

  testWidgets('guest lookup screen hides BKK guide for airport dropoff', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPage(
        GuestBookingLookupPage(
          lookupService: _FakeLookupService(
            _lookupResult(nameSign: false, serviceTypeCode: 'AIRPORT_DROPOFF'),
          ),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Gate 7'), findsNothing);
    expect(find.textContaining('Gate 3'), findsNothing);
  });

  testWidgets('guide renders without overflow across common widths', (
    tester,
  ) async {
    for (final width in <double>[360, 768, 1440]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        _wrap(
          const AirportMeetingGuideCard(
            serviceTypeCode: 'AIRPORT_PICKUP',
            originAirportCode: 'BKK',
            nameSignRequested: true,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
    'guide renders in EN KO TH JA ZH without fallback-only locale gaps',
    (tester) async {
      for (final locale in const [
        Locale('en'),
        Locale('ko'),
        Locale('th'),
        Locale('ja'),
        Locale('zh'),
      ]) {
        await tester.pumpWidget(
          _wrap(
            const AirportMeetingGuideCard(
              serviceTypeCode: 'AIRPORT_PICKUP',
              originAirportCode: 'BKK',
              nameSignRequested: false,
            ),
            locale: locale,
          ),
        );
        await tester.pump();

        expect(find.textContaining('airport_meeting_'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('en'),
      Locale('ko'),
      Locale('th'),
      Locale('ja'),
      Locale('zh'),
    ],
    localizationsDelegates: [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Widget _wrapPage(Widget child, {Locale locale = const Locale('en')}) {
  return wrapBookingCompleteTestApp(
    home: child,
    authController: _bookingCompleteAuthController,
    locale: locale,
  );
}

BookingCreateResult _bookingResult({String status = 'PENDING'}) {
  return BookingCreateResult(
    bookingId: 1,
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

GuestBookingLookupResult _lookupResult({
  required bool nameSign,
  String serviceTypeCode = 'AIRPORT_PICKUP',
  String originCode = 'BKK',
  String status = 'DRIVER_ASSIGNED',
  bool includeDriver = true,
}) {
  return GuestBookingLookupResult.fromJson({
    'bookingId': 1,
    'bookingNumber': 'TX202607010001',
    'status': status,
    'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
    'serviceType': {'code': serviceTypeCode, 'name': 'Airport Pickup'},
    'route': {
      'origin': {'code': originCode, 'address': 'BKK Airport'},
      'destination': {'code': 'PATTAYA', 'address': 'Pattaya Hotel'},
    },
    'options': {'nameSignRequested': nameSign},
    'pricing': {
      'totalAmount': 1500,
      'currency': 'THB',
      'paymentMethod': 'PAY_DRIVER',
    },
    'assignedDriver': includeDriver
        ? {
            'name': 'Driver A',
            'phone': '+66 80 000 0000',
            'vehicle': {
              'typeName': 'SUV',
              'color': 'Black',
              'plateNumber': '1錫곟툊1234',
            },
          }
        : null,
    'capabilities': {
      'notificationsAvailable': true,
      'dropoffQrIssueAvailable': false,
      'reviewAvailable': false,
      'boardingQrRecoverable': false,
      'boardingQrPreviouslyIssued': true,
    },
    'guestAccess': {
      'token': 'guest-token',
      'expiresAt': '2099-07-02T00:00:00Z',
    },
  });
}

class _FakeLookupService extends GuestBookingLookupService {
  _FakeLookupService(this.cached)
    : super(
        baseUrl: 'http://localhost:3000',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  final GuestBookingLookupResult cached;

  @override
  Future<GuestBookingLookupResult?> loadCached() async => cached;
}
