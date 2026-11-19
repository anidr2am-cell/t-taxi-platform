import '../../../l10n/app_localizations.dart';

String customerNotificationText(
  AppLocalizations l,
  Map<String, dynamic> item,
  String field,
) {
  final original = item[field] as String? ?? '';
  if (original.isEmpty && field == 'title')
    return l.t('booking_notification_default_title');
  final key = 'cx_notice_${item['notificationType']}';
  final english = AppLocalizations('en').t(key);
  final localized = l.t(key);
  if (english == key || localized == key) return original;
  final target = localized.split('\n');
  final sources = [
    english.split('\n'),
    // Older stored notices used the driver-facing default. Correct the customer
    // view without rewriting stored notices or changing driver notifications.
    if (item['notificationType'] == 'DRIVER_REASSIGNED')
      ['Booking reassigned', 'You have been assigned to a new booking.'],
  ];
  final index = field == 'title' ? 0 : 1;
  if (target.length <= index) return original;
  // Do not rewrite customized messages. Preserve booking-number suffixes.
  for (final source in sources) {
    if (source.length <= index || !original.startsWith(source[index])) continue;
    final suffix = original.substring(source[index].length);
    if (index == 0 && suffix.isNotEmpty) continue;
    if (index == 1 &&
        suffix.isNotEmpty &&
        !RegExp(r'^ \(TX\d{12}\)$').hasMatch(suffix))
      continue;
    return target[index] + suffix;
  }
  return original;
}
