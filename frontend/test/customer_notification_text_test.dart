import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/utils/customer_notification_text.dart';

void main() {
  for (final language in ['ko', 'en', 'th', 'ja', 'zh']) {
    test(
      'default customer notices localize in $language and preserve booking number',
      () {
        final l = AppLocalizations(language),
            n = {
              'notificationType': 'BOOKING_CREATED',
              'title': 'Booking created',
              'body': 'Your booking has been created. (TX202610170001)',
            };
        expect(
          customerNotificationText(l, n, 'body'),
          endsWith(' (TX202610170001)'),
        );
        if (language != 'en')
          expect(
            customerNotificationText(l, n, 'body'),
            isNot(contains('Your booking')),
          );
        expect(
          customerNotificationText(l, n, 'title'),
          l.t('cx_notice_BOOKING_CREATED').split('\n').first,
        );
      },
    );
  }
  test('customized and unknown messages retain their original content', () {
    final l = AppLocalizations('ko');
    expect(
      customerNotificationText(l, {
        'notificationType': 'BOOKING_CREATED',
        'body': 'Your booking has been created. Please call support.',
      }, 'body'),
      'Your booking has been created. Please call support.',
    );
    expect(
      customerNotificationText(l, {
        'notificationType': 'CUSTOM',
        'body': '관리자 안내',
      }, 'body'),
      '관리자 안내',
    );
  });
  test('missing notification title uses localized fallback', () {
    final l = AppLocalizations('ko');
    expect(
      customerNotificationText(l, {}, 'title'),
      l.t('booking_notification_default_title'),
    );
  });
}
