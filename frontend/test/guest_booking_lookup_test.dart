import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('lookup posts booking number and phone then persists guest access', () async {
    Uri? requestedUri;
    Map<String, dynamic>? body;
    final service = GuestBookingLookupService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        requestedUri = request.url;
        body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(jsonEncode({
          'success': true,
          'data': _lookupJson(),
        }), 200);
      }),
    );

    final result = await service.lookup(
      bookingNumber: 'tx202607010001',
      phone: '+66 (81) 234-5678',
    );

    expect(requestedUri!.path, '/api/v1/public/bookings/lookup');
    expect(body, {
      'bookingNumber': 'tx202607010001',
      'phone': '+66 (81) 234-5678',
    });
    expect(result.bookingNumber, 'TX202607010001');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('guest_access_token_TX202607010001'),
      'guest-token',
    );
  });

  testWidgets('lookup page restores cached booking on refresh', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GuestBookingLookupPage(
        lookupService: _FakeLookupService(cached: _result()),
        enableCustomerTools: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TX202607010001'), findsOneWidget);
    expect(find.text('PICKED_UP'), findsOneWidget);
    expect(find.text('Issue dropoff QR'), findsOneWidget);
  });

  testWidgets('lookup page shows controlled not-found error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GuestBookingLookupPage(
        lookupService: _FakeLookupService(errorCode: 'BOOKING_NOT_FOUND'),
        enableCustomerTools: false,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_booking_number')),
      'TX202607010001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_phone')),
      '+66 81 234 5670',
    );
    await tester.tap(find.text('Find booking'));
    await tester.pumpAndSettle();

    expect(
      find.text('Booking not found. Please check your booking number and phone.'),
      findsOneWidget,
    );
  });

  testWidgets('malformed successful response becomes controlled error state', (tester) async {
    final service = GuestBookingLookupService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        return http.Response(jsonEncode({
          'success': true,
          'data': {'bookingNumber': 'TX202607010001'},
        }), 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: GuestBookingLookupPage(
        lookupService: service,
        enableCustomerTools: false,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_booking_number')),
      'TX202607010001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_phone')),
      '+66 81 234 5678',
    );
    await tester.tap(find.text('Find booking'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load booking. Please try again.'), findsOneWidget);
  });
}

Map<String, dynamic> _lookupJson() => {
      'bookingNumber': 'TX202607010001',
      'status': 'PICKED_UP',
      'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
      'serviceType': {'name': 'Airport Pickup'},
      'route': {
        'origin': {'address': 'BKK Airport'},
        'destination': {'address': 'Pattaya Hotel'},
      },
      'pricing': {
        'totalAmount': 1500,
        'currency': 'THB',
        'paymentMethod': 'PAY_DRIVER',
      },
      'assignedDriver': {'name': 'Driver A', 'phone': '+66 80 000 0000'},
      'capabilities': {
        'chatAvailable': true,
        'notificationsAvailable': true,
        'dropoffQrIssueAvailable': true,
        'reviewAvailable': false,
        'boardingQrRecoverable': false,
        'boardingQrPreviouslyIssued': true,
      },
      'guestAccess': {
        'token': 'guest-token',
        'expiresAt': '2099-07-02T00:00:00Z',
      },
    };

GuestBookingLookupResult _result() {
  return GuestBookingLookupResult.fromJson(_lookupJson());
}

class _FakeLookupService extends GuestBookingLookupService {
  _FakeLookupService({this.cached, this.errorCode})
      : super(
          baseUrl: 'http://localhost:3000',
          client: MockClient((_) async => http.Response('{}', 200)),
        );

  final GuestBookingLookupResult? cached;
  final String? errorCode;

  @override
  Future<GuestBookingLookupResult?> loadCached() async => cached;

  @override
  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
  }) async {
    if (errorCode != null) {
      throw BookingApiException('Booking not found', errorCode);
    }
    return cached ?? _result();
  }
}
