import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_trip_flow.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';

void main() {
  test('primary action follows trip button flow order', () {
    final assigned = _booking(
      status: 'DRIVER_ASSIGNED',
      actions: ['START_ON_ROUTE'],
    );
    expect(DriverTripFlow.primaryActionToken(assigned), 'START_ON_ROUTE');
    expect(
      DriverTripFlow.primaryActionLabelKey(assigned),
      'driver_action_start_on_route',
    );

    final onRoute = _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']);
    expect(DriverTripFlow.primaryActionToken(onRoute), 'MARK_ARRIVED');

    final arrived = _booking(
      status: 'DRIVER_ARRIVED',
      actions: ['MARK_PICKED_UP'],
    );
    expect(DriverTripFlow.primaryActionToken(arrived), 'MARK_PICKED_UP');

    final pickedUp = _booking(status: 'PICKED_UP', actions: ['END_TRIP']);
    expect(DriverTripFlow.primaryActionToken(pickedUp), 'END_TRIP');

    final settlement = _booking(status: 'SETTLEMENT_PENDING', actions: []);
    expect(DriverTripFlow.primaryActionToken(settlement), isNull);
  });
}

DriverBooking _booking({
  required String status,
  required List<String> actions,
}) {
  return DriverBooking(
    bookingNumber: 'TX202607010001',
    status: status,
    serviceTypeName: 'Airport Pickup',
    pickupDate: '2026-07-01',
    pickupTime: '09:30',
    origin: 'BKK Airport',
    destination: 'Pattaya Hotel',
    passengerCount: 2,
    vehicleTypeName: 'SUV',
    allowedActions: actions,
  );
}
