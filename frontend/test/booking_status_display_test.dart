import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/booking_status_display.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('statusLabelKey maps booking statuses consistently', () {
    expect(BookingStatusDisplay.statusLabelKey('PENDING'), 'status_pending');
    expect(BookingStatusDisplay.statusLabelKey('ON_ROUTE'), 'status_on_route');
    expect(
      BookingStatusDisplay.statusLabelKey('DRIVER_ARRIVED'),
      'status_driver_arrived',
    );
    expect(BookingStatusDisplay.statusLabelKey('NO_SHOW'), 'status_no_show');
  });

  test('SETTLEMENT_PENDING labels differ by audience', () {
    expect(
      BookingStatusDisplay.statusLabelKey(
        'SETTLEMENT_PENDING',
        audience: BookingStatusAudience.customer,
      ),
      'status_customer_settlement_pending',
    );
    expect(
      BookingStatusDisplay.statusLabelKey(
        'SETTLEMENT_PENDING',
        audience: BookingStatusAudience.driver,
      ),
      'status_driver_settlement_pending',
    );
    expect(
      BookingStatusDisplay.statusLabelKey(
        'SETTLEMENT_PENDING',
        audience: BookingStatusAudience.admin,
      ),
      'status_admin_settlement_pending',
    );
  });

  test('customer SETTLEMENT_PENDING copy avoids settlement wording', () {
    final en = AppLocalizations('en');
    final ko = AppLocalizations('ko');
    final th = AppLocalizations('th');

    final enLabel = BookingStatusDisplay.label(
      en,
      'SETTLEMENT_PENDING',
      audience: BookingStatusAudience.customer,
    );
    final enGuidance = BookingStatusDisplay.customerGuidance(
      en,
      'SETTLEMENT_PENDING',
    )!;

    expect(enLabel.toLowerCase(), isNot(contains('settlement')));
    expect(enGuidance.toLowerCase(), isNot(contains('settlement')));
    expect(enGuidance, contains('Please rate your driver'));

    final koLabel = BookingStatusDisplay.label(
      ko,
      'SETTLEMENT_PENDING',
      audience: BookingStatusAudience.customer,
    );
    final koGuidance = BookingStatusDisplay.customerGuidance(
      ko,
      'SETTLEMENT_PENDING',
    )!;
    expect(koLabel, isNot(contains('정산')));
    expect(koGuidance, isNot(contains('정산')));
    expect(koGuidance, contains('평가'));

    final thGuidance = BookingStatusDisplay.customerGuidance(
      th,
      'SETTLEMENT_PENDING',
    )!;
    expect(thGuidance, contains('กรุณาให้คะแนนคนขับ'));
  });

  test('admin SETTLEMENT_PENDING label keeps settlement wording', () {
    final ko = AppLocalizations('ko');
    final label = BookingStatusDisplay.label(
      ko,
      'SETTLEMENT_PENDING',
      audience: BookingStatusAudience.admin,
    );
    expect(label, contains('정산'));
  });

  test('label returns localized text', () {
    final l10n = AppLocalizations('en');
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
      'SETTLEMENT_PENDING',
      'COMPLETED',
      'CANCELLED',
      'NO_SHOW',
    ]) {
      expect(BookingStatusDisplay.customerGuidanceKey(status), isNotNull);
    }
  });

  test('customerGuidance returns readable copy', () {
    final l10n = AppLocalizations('en');
    expect(
      BookingStatusDisplay.customerGuidance(l10n, 'PENDING'),
      contains('received'),
    );
  });
}
