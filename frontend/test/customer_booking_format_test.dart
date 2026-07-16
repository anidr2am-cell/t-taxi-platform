import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/customer_booking_format.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('formats THB without exposing raw currency layout', () {
    expect(CustomerBookingFormat.money(1300, 'THB'), '฿1,300');
    expect(CustomerBookingFormat.money(1300.4, 'thb'), '฿1,300');
  });

  test('formats non-THB with normalized currency', () {
    expect(CustomerBookingFormat.money(1300, 'usd'), '1,300 USD');
  });

  test('maps payment methods without exposing raw codes', () {
    final l10n = AppLocalizations('en');

    expect(
      CustomerBookingFormat.paymentMethod(l10n, 'PAY_DRIVER'),
      'Pay the driver at the destination',
    );
    expect(
      CustomerBookingFormat.paymentMethod(l10n, 'BANK_TRANSFER'),
      'Bank transfer',
    );
    expect(
      CustomerBookingFormat.paymentMethod(l10n, 'FUTURE_PROVIDER'),
      'Payment method unavailable',
    );
    expect(
      CustomerBookingFormat.paymentMethod(l10n, 'FUTURE_PROVIDER'),
      isNot(contains('FUTURE_PROVIDER')),
    );
  });

  test('keeps +07 pickup date and time as Thailand wall time', () {
    final en = AppLocalizations('en');
    final ko = AppLocalizations('ko');
    final th = AppLocalizations('th');

    expect(
      CustomerBookingFormat.pickupDateTime(en, '2026-07-18T00:30:00+07:00'),
      'Jul 18, 2026, 12:30 AM',
    );
    expect(
      CustomerBookingFormat.pickupDateTime(ko, '2026-07-18T14:30:00+07:00'),
      '2026년 7월 18일 오후 2:30',
    );
    expect(
      CustomerBookingFormat.pickupDateTime(th, '2026-07-18T14:30:00+07:00'),
      '18 ก.ค. 2026 14:30',
    );
  });

  test('does not expose raw ISO on invalid pickup datetime', () {
    final l10n = AppLocalizations('en');

    expect(CustomerBookingFormat.pickupDateTime(l10n, 'not-a-date'), '-');
    expect(
      CustomerBookingFormat.pickupDateTime(l10n, 'not-a-date'),
      isNot(contains('not-a-date')),
    );
  });
}
