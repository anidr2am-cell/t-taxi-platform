import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver_location/utils/driver_search.dart';

void main() {
  const driver = {
    'driverId': 6,
    'displayName': 'สมชาย Somchai',
    'phone': '+66 81-234-5678',
    'primaryVehicle': {'plateNumber': 'กข 1234', 'modelName': 'Toyota Camry'},
    'vehiclePlateNumbers': ['กข 1234', 'AB-5678'],
  };

  test('matches partial names, all vehicle plates, model and driver ID', () {
    for (final query in ['สมชาย', 'SOMCHAI', 'กข1234', 'ab 5678', 'camry', '6', '']) {
      expect(matchesDriverSearch(driver, query), isTrue, reason: query);
    }
    expect(matchesDriverSearch(driver, 'missing-driver'), isFalse);
  });

  test('Thai domestic and international phone formats match in either direction', () {
    for (final phone in ['+66 81-234-5678', '081-234-5678']) {
      final entry = {...driver, 'phone': phone};
      for (final query in ['0812345678', '+66812345678', '234-5678']) {
        expect(matchesDriverSearch(entry, query), isTrue, reason: '$phone / $query');
      }
    }
  });

  test('legacy drivers without vehicle search fields remain searchable', () {
    expect(matchesDriverSearch({'displayName': 'Driver A'}, 'driver a'), isTrue);
    expect(matchesDriverSearch({}, 'missing'), isFalse);
  });
}
