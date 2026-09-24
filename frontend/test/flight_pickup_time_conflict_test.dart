import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/flight_pickup_time_conflict.dart';
import 'package:frontend/features/booking/utils/thailand_pickup_datetime.dart';

void main() {
  test('shows conflict when manual pickup and flight arrival differ by 30+ minutes', () {
    final manual = DateTime(2026, 9, 24, 10, 0);
    final flightArrival = DateTime(2026, 9, 24, 12, 0);
    expect(
      shouldShowFlightPickupConflict(
        manualPickupBangkok: manual,
        flightArrivalBangkok: flightArrival,
      ),
      isTrue,
    );
    expect(absoluteMinuteDifference(manual, flightArrival), 120);
  });

  test('no conflict when difference is under 30 minutes', () {
    final manual = DateTime(2026, 9, 24, 10, 0);
    final flightArrival = DateTime(2026, 9, 24, 10, 20);
    expect(
      shouldShowFlightPickupConflict(
        manualPickupBangkok: manual,
        flightArrivalBangkok: flightArrival,
      ),
      isFalse,
    );
  });

  test('Thailand serialize and restore round-trip for admin pickup', () {
    const iso = '2026-09-24T03:30:00.000Z';
    final wall = ThailandPickupDateTime.bangkokWallFromIso(iso);
    expect(wall.hour, 10);
    expect(wall.minute, 30);
    final serialized = ThailandPickupDateTime.serializeWallClock(wall);
    expect(serialized, '2026-09-24T10:30:00+07:00');
    final restored = ThailandPickupDateTime.tryBangkokWallFromIso(
      DateTime.parse(serialized).toUtc().toIso8601String(),
    );
    expect(restored?.hour, 10);
    expect(restored?.minute, 30);
  });

  test('bangkokWallClockFromFlightIso matches UTC+7 wall clock', () {
    final wall = bangkokWallClockFromFlightIso('2026-09-24T05:00:00.000Z');
    expect(wall, DateTime(2026, 9, 24, 12, 0));
  });
}
