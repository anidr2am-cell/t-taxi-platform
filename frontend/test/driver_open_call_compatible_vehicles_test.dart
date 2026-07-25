import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';

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
}
