import '../../../l10n/app_localizations.dart';
import '../../driver/utils/driver_backend_datetime.dart';

class AdminDriverCheckMessage {
  const AdminDriverCheckMessage({
    required this.id,
    required this.titleKey,
    required this.thai,
    required this.korean,
  });
  final String id;
  final String titleKey;
  final String thai;
  final String korean;
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _text(dynamic value) {
  if (value is! String) return '';
  final result = value.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return result == '-' || result.toLowerCase() == 'null' ? '' : result;
}

/// No customer contact fields, API calls or inferred departure/ETA values.
List<AdminDriverCheckMessage> buildAdminDriverCheckMessages(
  Map<String, dynamic> detail,
) {
  final raw = _text(detail['scheduledPickupAt']);
  final parsed = parseBackendServiceDateTime(raw);
  final bangkok = parsed?.toUtc().add(const Duration(hours: 7));
  final formatted = formatBackendServiceDateTimeBangkok(raw);
  final route = _map(detail['route']);
  final origin = _map(route['origin']);
  final placeName = [
    _text(origin['nameTh']),
    _text(origin['name']),
    _text(origin['displayName']),
  ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
  final address = _text(origin['address']);
  final place = [
    placeName,
    if (address != placeName) address,
  ].where((s) => s.isNotEmpty).join(' · ');
  final assignmentRaw = _map(detail['activeAssignment']);
  final assignment = assignmentRaw['isActive'] == false
      ? <String, dynamic>{}
      : assignmentRaw;
  final vehicle = _map(assignment['vehicle']);

  String render(String language, String bodyKey, {bool includeContext = true}) {
    final l10n = AppLocalizations(language);
    final missing = l10n.t('admin_driver_check_missing');
    String value(String s) => s.isEmpty ? missing : s;
    final values = {
      'booking': value(_text(detail['bookingNumber'])),
      'date': formatted?.split(' ').first ?? missing,
      'time': formatted?.split(' ').last ?? missing,
      'weekday': bangkok == null
          ? missing
          : l10n.t('admin_driver_check_weekdays').split('|')[bangkok.weekday -
                1],
      'pickup': value(place),
      // Assigned records are only reference information, never proof of the actual driver.
      'driver': value(_text(assignment['driverDisplayName'])),
      'plate': value(_text(vehicle['plateNumber'])),
    };
    final reply =
        bodyKey.endsWith('_handoff_body') || bodyKey.endsWith('_pre_body')
        ? '\n\n${l10n.t('admin_driver_check_reply_body')}'
        : '';
    final template = includeContext
        ? '${l10n.t('admin_driver_check_context')}\n\n${l10n.t(bodyKey)}$reply'
        : l10n.t(bodyKey);
    return template.replaceAllMapped(
      RegExp(r'\{(booking|date|time|weekday|pickup|driver|plate)\}'),
      (m) => values[m.group(1)]!,
    );
  }

  return ['handoff', 'pre', 'reply', 'reminder']
      .map((id) {
        final body = 'admin_driver_check_${id}_body';
        return AdminDriverCheckMessage(
          id: id,
          titleKey: 'admin_driver_check_$id',
          thai: render('th', body, includeContext: id != 'reminder'),
          korean: render('ko', body, includeContext: id != 'reminder'),
        );
      })
      .toList(growable: false);
}
