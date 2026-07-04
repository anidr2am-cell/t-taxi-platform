import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/booking_status_display.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  final l10n = AppLocalizations('en');

  test('statusLabelKey maps booking statuses consistently', () {
    expect(BookingStatusDisplay.statusLabelKey('PENDING'), 'status_pending');
    expect(BookingStatusDisplay.statusLabelKey('ON_ROUTE'), 'status_on_route');
    expect(
      BookingStatusDisplay.statusLabelKey('DRIVER_ARRIVED'),
      'status_driver_arrived',
    );
    expect(BookingStatusDisplay.statusLabelKey('NO_SHOW'), 'status_no_show');
  });

  test('label returns localized text', () {
    expect(BookingStatusDisplay.label(l10n, 'ON_ROUTE'), 'On the way');
    expect(
      BookingStatusDisplay.label(l10n, 'DRIVER_ASSIGNED'),
      'Driver Assigned',
    );
  });

  test('customerGuidanceKey covers MVP statuses', () {
    for (final status in [
      'PENDING',
      'CONFIRMED',
      'DRIVER_ASSIGNED',
      'ON_ROUTE',
      'DRIVER_ARRIVED',
      'COMPLETED',
      'CANCELLED',
      'NO_SHOW',
    ]) {
      expect(BookingStatusDisplay.customerGuidanceKey(status), isNotNull);
    }
  });

  test('customerGuidance returns readable copy', () {
    expect(
      BookingStatusDisplay.customerGuidance(l10n, 'PENDING'),
      contains('received'),
    );
  });
}
