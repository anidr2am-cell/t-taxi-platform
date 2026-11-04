import '../../../l10n/app_localizations.dart';
import '../../driver/utils/driver_backend_datetime.dart';

Map<String, dynamic> briefMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String briefText(dynamic value) => value?.toString().trim() ?? '';

/// A customer-facing allowlist. Never include company commission, driver payout,
/// admin notes, customer contact details or guest access tokens.
String buildAdminCustomerBrief(Map<String, dynamic> detail, String locale) {
  final assignment = briefMap(detail['activeAssignment']);
  if (assignment.isEmpty || assignment['isActive'] == false) return '';
  final l = AppLocalizations(locale);
  String t(String key) => l.t('admin_customer_brief_$key');
  String line(String key, dynamic value) =>
      '${t(key)}: ${briefText(value).isEmpty ? '-' : briefText(value)}';
  String place(dynamic value) {
    final p = briefMap(value);
    final name = briefText(
      p['name${locale[0].toUpperCase()}${locale.substring(1)}'],
    );
    return [
      if (name.isNotEmpty) name else briefText(p['name']),
      briefText(p['address']),
    ].where((s) => s.isNotEmpty).toSet().join(' · ');
  }

  final vehicle = briefMap(assignment['vehicle']);
  final route = briefMap(detail['route']);
  final flight = briefMap(detail['flight']);
  return [
    'T-Rider · ${t('title')}',
    line('number', detail['bookingNumber']),
    line(
      'pickup',
      formatBackendServiceDateTimeBangkok(
        briefText(detail['scheduledPickupAt']),
      ),
    ),
    line('origin', place(route['origin'])),
    line('destination', place(route['destination'])),
    if (briefText(flight['flightNumber']).isNotEmpty)
      line('flight', flight['flightNumber']),
    line('driver', assignment['driverDisplayName']),
    line(
      'vehicle',
      [
        vehicle['modelName'],
        vehicle['color'],
      ].map(briefText).where((s) => s.isNotEmpty).join(' · '),
    ),
    line('plate', vehicle['plateNumber']),
    if (briefText(detail['specialRequests']).isNotEmpty)
      line('requests', detail['specialRequests']),
    '',
    t('notice'),
  ].join('\n');
}
