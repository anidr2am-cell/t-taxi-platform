import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/utils/admin_booking_json_values.dart';

void main() {
  test('adminBookingJsonNum accepts num and string', () {
    expect(adminBookingJsonNum(850), 850);
    expect(adminBookingJsonNum('850'), 850);
    expect(adminBookingJsonNum(' 850.5 '), 850.5);
    expect(adminBookingJsonNum(null), isNull);
    expect(adminBookingJsonNum(''), isNull);
    expect(adminBookingJsonNum('not-a-number'), isNull);
  });
}
