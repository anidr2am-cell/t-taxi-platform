import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/thailand_pickup_datetime.dart';

void main() {
  test('bangkok wall clock round trip from UTC ISO', () {
    const iso = '2026-09-24T03:30:00.000Z';
    final wall = ThailandPickupDateTime.bangkokWallFromIso(iso);
    expect(wall.hour, 10);
    expect(wall.minute, 30);
    expect(
      ThailandPickupDateTime.serializeWallClock(wall),
      '2026-09-24T10:30:00+07:00',
    );
  });

  test('date picker first date includes past pickup on edit', () {
    final today = DateTime(2026, 9, 24);
    final pastPickup = DateTime(2026, 9, 10, 8, 0);
    final first = ThailandPickupDateTime.datePickerFirstDate(
      thailandToday: today,
      currentPickup: pastPickup,
    );
    expect(first, DateTime(2026, 9, 10));
  });
}
