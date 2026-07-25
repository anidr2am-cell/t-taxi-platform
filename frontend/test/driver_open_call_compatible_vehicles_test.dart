import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/pages/driver_jobs_page.dart';

import 'support/driver_ux_qa_harness.dart';

void main() {
  test('DriverOpenCall parses compatibleVehicles for claim picker', () {
    final call = DriverOpenCall.fromJson({
      'bookingNumber': 'TX202607250001',
      'status': 'OPEN',
      'pickupDate': '2026-07-25',
      'pickupTime': '10:00',
      'origin': 'A',
      'destination': 'B',
      'serviceType': {'name': 'Airport'},
      'vehicleType': {'name': 'Sedan', 'code': 'SEDAN'},
      'amount': 1000,
      'currency': 'THB',
      'passengerCount': 2,
      'compatibleVehicles': [
        {
          'driverVehicleId': 11,
          'vehicleTypeCode': 'SEDAN',
          'vehicleTypeName': 'Sedan',
          'plateNumber': 'S-1',
          'isExactMatch': true,
        },
        {
          'driverVehicleId': 22,
          'vehicleTypeCode': 'VAN',
          'vehicleTypeName': 'Van',
          'plateNumber': 'V-1',
          'isExactMatch': false,
        },
      ],
    });

    expect(call.compatibleVehicles.length, 2);
    expect(call.compatibleVehicles.first.driverVehicleId, 11);
    expect(call.compatibleVehicles.last.plateNumber, 'V-1');
    expect(call.compatibleVehicles.last.isExactMatch, isFalse);
  });

  test('single compatible vehicle means picker is unnecessary', () {
    final call = DriverOpenCall.fromJson({
      'bookingNumber': 'TX202607250002',
      'status': 'OPEN',
      'pickupDate': '2026-07-25',
      'pickupTime': '10:00',
      'origin': 'A',
      'destination': 'B',
      'serviceType': {'name': 'Airport'},
      'vehicleType': {'name': 'Sedan', 'code': 'SEDAN'},
      'amount': 1000,
      'currency': 'THB',
      'passengerCount': 1,
      'compatibleVehicles': [
        {
          'driverVehicleId': 11,
          'vehicleTypeCode': 'SEDAN',
          'vehicleTypeName': 'Sedan',
          'plateNumber': 'S-1',
          'isExactMatch': true,
        },
      ],
    });

    expect(call.compatibleVehicles.length, 1);
    expect(call.compatibleVehicles.length >= 2, isFalse);
  });

  testWidgets(
    'claim with two+ compatible vehicles shows picker and claims the selected vehicle',
    (tester) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(800, 1400),
      );
      final call = qaOpenCall(number: 'TX202607250003').copyWith(
        compatibleVehicles: const [
          DriverOpenCallCompatibleVehicle(
            driverVehicleId: 11,
            vehicleTypeCode: 'SEDAN',
            vehicleTypeName: 'Sedan',
            plateNumber: 'S-100',
            isExactMatch: true,
          ),
          DriverOpenCallCompatibleVehicle(
            driverVehicleId: 22,
            vehicleTypeCode: 'VAN',
            vehicleTypeName: 'Van',
            plateNumber: 'V-200',
            isExactMatch: false,
          ),
        ],
      );
      final api = QaDriverApi(online: true, openCalls: [call]);
      await tester.pumpWidget(DriverUxQaHarness.page(DriverJobsPage(api: api)));
      await tester.pumpAndSettle();

      final claimButton = find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้');
      await tester.scrollUntilVisible(
        claimButton,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(claimButton);
      await tester.tap(claimButton.first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
        ),
      );
      await tester.pumpAndSettle();

      // Two compatible vehicles: the vehicle picker must appear before claiming.
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(api.claimCalls, 0);
      expect(find.text('S-100'), findsOneWidget);
      expect(find.text('V-200'), findsOneWidget);

      await tester.tap(find.text('V-200'));
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsNothing);
      expect(api.claimCalls, 1);
      expect(api.lastClaimedDriverVehicleId, 22);
      expect(find.byType(DriverBookingDetailPage), findsOneWidget);
    },
  );

  testWidgets(
    'claim with a single compatible vehicle skips the picker entirely',
    (tester) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(800, 1400),
      );
      final call = qaOpenCall(number: 'TX202607250004').copyWith(
        compatibleVehicles: const [
          DriverOpenCallCompatibleVehicle(
            driverVehicleId: 33,
            vehicleTypeCode: 'SEDAN',
            vehicleTypeName: 'Sedan',
            plateNumber: 'S-300',
            isExactMatch: true,
          ),
        ],
      );
      final api = QaDriverApi(online: true, openCalls: [call]);
      await tester.pumpWidget(DriverUxQaHarness.page(DriverJobsPage(api: api)));
      await tester.pumpAndSettle();

      final claimButton = find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้');
      await tester.scrollUntilVisible(
        claimButton,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(claimButton);
      await tester.tap(claimButton.first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsNothing);
      expect(api.claimCalls, 1);
      expect(api.lastClaimedDriverVehicleId, 33);
      expect(find.byType(DriverBookingDetailPage), findsOneWidget);
    },
  );
}
