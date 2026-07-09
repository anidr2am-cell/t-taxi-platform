import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:frontend/features/booking/widgets/assigned_driver_status_card.dart';
import 'package:frontend/features/booking/widgets/guest_driver_vehicle_photo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('assigned driver card is hidden before driver assignment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignedDriverStatusCard(
            result: GuestBookingLookupResult.fromJson(_lookupJson()),
          ),
        ),
      ),
    );

    expect(find.text('Driver status'), findsNothing);
  });

  testWidgets('assigned driver card shows vehicle photo after assignment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignedDriverStatusCard(
            result: GuestBookingLookupResult.fromJson(_lookupJson(
              assignedDriver: {
                'name': 'Driver A',
                'phone': '+66 80 000 0000',
                'vehicle': {
                  'typeName': 'SUV',
                  'color': 'Black',
                  'plateNumber': '1กข1234',
                  'vehiclePhotoUrl':
                      '/api/v1/public/bookings/10/assigned-driver-vehicle-photo',
                },
              },
            )),
            apiBaseUrl: 'http://localhost:3000',
          ),
        ),
      ),
    );

    expect(find.text('Driver status'), findsOneWidget);
    expect(find.text('Driver A'), findsOneWidget);
    expect(find.text('SUV · Black · 1กข1234'), findsOneWidget);
    expect(find.byType(GuestDriverVehiclePhoto), findsOneWidget);
  });

  testWidgets('vehicle photo widget shows load failure message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverVehiclePhoto(
            photoPath: '/api/v1/public/bookings/10/assigned-driver-vehicle-photo',
            guestAccessToken: 'guest-token',
            apiBaseUrl: 'http://localhost:3000',
            client: MockClient((request) async {
              return http.Response('not found', 404);
            }),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Unable to load vehicle photo.'), findsOneWidget);
  });

  testWidgets('vehicle photo widget renders fetched image bytes', (tester) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestDriverVehiclePhoto(
            photoPath: '/api/v1/public/bookings/10/assigned-driver-vehicle-photo',
            guestAccessToken: 'guest-token',
            apiBaseUrl: 'http://localhost:3000',
            client: MockClient((request) async {
              expect(request.headers['X-Guest-Access-Token'], 'guest-token');
              return http.Response.bytes(bytes, 200, headers: {
                'content-type': 'image/jpeg',
              });
            }),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Unable to load vehicle photo.'), findsNothing);
  });

  testWidgets('lookup page shows driver card below booking number when assigned', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(
            cached: GuestBookingLookupResult.fromJson(_lookupJson(
              assignedDriver: {
                'name': 'Driver A',
                'phone': '+66 80 000 0000',
                'vehicle': {
                  'typeName': 'SUV',
                  'vehiclePhotoUrl':
                      '/api/v1/public/bookings/10/assigned-driver-vehicle-photo',
                },
              },
            )),
          ),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TX202607010001'), findsOneWidget);
    expect(find.text('Driver status'), findsOneWidget);
    expect(find.byType(GuestDriverVehiclePhoto), findsOneWidget);
  });

  testWidgets('lookup page has no horizontal overflow at 360px with driver photo card', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(
            cached: GuestBookingLookupResult.fromJson(_lookupJson(
              assignedDriver: {
                'name': 'Driver A',
                'vehicle': {
                  'typeName': 'SUV',
                  'vehiclePhotoUrl':
                      '/api/v1/public/bookings/10/assigned-driver-vehicle-photo',
                },
              },
            )),
          ),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _lookupJson({Map<String, dynamic>? assignedDriver}) => {
      'bookingId': 10,
      'bookingNumber': 'TX202607010001',
      'status': 'DRIVER_ASSIGNED',
      'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
      'serviceType': {'name': 'Airport Pickup', 'code': 'AIRPORT_PICKUP'},
      'route': {
        'origin': {'address': 'BKK Airport', 'code': 'BKK'},
        'destination': {'address': 'Pattaya Hotel', 'code': 'PATTAYA'},
      },
      'pricing': {
        'totalAmount': 1500,
        'currency': 'THB',
        'paymentMethod': 'PAY_DRIVER',
      },
      if (assignedDriver != null) 'assignedDriver': assignedDriver,
      'capabilities': {
        'chatAvailable': true,
        'notificationsAvailable': true,
        'dropoffQrIssueAvailable': false,
        'reviewAvailable': false,
        'boardingQrRecoverable': false,
        'boardingQrPreviouslyIssued': false,
      },
      'guestAccess': {
        'token': 'guest-token',
        'expiresAt': '2099-07-02T00:00:00Z',
      },
    };

class _FakeLookupService extends GuestBookingLookupService {
  _FakeLookupService({required this.cached})
      : super(
          baseUrl: 'http://localhost:3000',
          client: MockClient((_) async => http.Response('{}', 200)),
        );

  final GuestBookingLookupResult cached;

  @override
  Future<GuestBookingLookupResult?> loadCached() async => cached;

  @override
  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
  }) async {
    return cached;
  }
}
