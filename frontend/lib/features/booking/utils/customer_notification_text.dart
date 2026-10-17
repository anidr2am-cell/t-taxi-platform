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
  final source = english.split('\n'), target = localized.split('\n');
  final index = field == 'title' ? 0 : 1;
  if (source.length <= index || target.length <= index) return original;
  // Do not rewrite customized messages. Preserve booking-number suffixes.
  if (!original.startsWith(source[index])) return original;
  final suffix = original.substring(source[index].length);
  if (index == 0 && suffix.isNotEmpty) return original;
  if (index == 1 &&
      suffix.isNotEmpty &&
      !RegExp(r'^ \(TX\d{12}\)$').hasMatch(suffix))
    return original;
  return target[index] + suffix;
}
