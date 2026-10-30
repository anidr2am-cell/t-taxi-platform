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
  String place(dynamic endpoint, String missing) {
    final location = _map(endpoint);
    final name = [
      _text(location['nameTh']),
      _text(location['name']),
      _text(location['displayName']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final address = _text(location['address']);
    final parts = [
      name,
      if (address != name) address,
    ].where((v) => v.isNotEmpty).join(' · ');
    return parts.isEmpty ? missing : parts;
  }

  final assignmentRaw = _map(detail['activeAssignment']);
  final assignment = assignmentRaw['isActive'] == false
      ? <String, dynamic>{}
      : assignmentRaw;
  final vehicle = _map(assignment['vehicle']);

  String render(String language) {
    final l10n = AppLocalizations(language);
    final missing = l10n.t('admin_driver_check_missing');
    String value(String s) => s.isEmpty ? missing : s;
    String count(dynamic n) => n is num && n >= 0 && n == n.roundToDouble()
        ? n.toInt().toString()
        : missing;
    final thai = language == 'th';
    final serviceNames = thai
        ? {
            'AIRPORT_PICKUP': 'รับจากสนามบิน',
            'AIRPORT_DROPOFF': 'ส่งสนามบิน',
            'CITY_TRANSFER': 'เดินทางระหว่างเมือง',
            'GOLF_TRANSFER': 'รับส่งสนามกอล์ฟ',
          }
        : {
            'AIRPORT_PICKUP': '공항 픽업',
            'AIRPORT_DROPOFF': '공항 샌딩',
            'CITY_TRANSFER': '도시간 이동',
            'GOLF_TRANSFER': '골프 이동',
          };
    final vehicleNames = thai
        ? {'SEDAN': 'ซีดาน', 'SUV': 'เอสยูวี', 'VAN': 'รถตู้'}
        : {'SEDAN': '세단', 'SUV': 'SUV', 'VAN': '밴'};
    final passengers = _map(detail['passengers']);
    final luggage = _map(detail['luggage']);
    final flight = _map(detail['flight']);
    final flightNumber = _text(flight['flightNumber']);
    final options = _map(detail['options']);
    final values = {
      'booking': value(_text(detail['bookingNumber'])),
      'service':
          serviceNames[_text(_map(detail['serviceType'])['code'])] ?? missing,
      'date': formatted?.split(' ').first ?? missing,
      'time': formatted?.split(' ').last ?? missing,
      'weekday': bangkok == null
          ? missing
          : l10n.t('admin_driver_check_weekdays').split('|')[bangkok.weekday -
                1],
      'pickup': place(route['origin'], missing),
      'destination': place(route['destination'], missing),
      'vehicleType':
          vehicleNames[_text(_map(detail['vehicle'])['typeCode'])] ?? missing,
      'adults': count(passengers['adults']),
      'children': count(passengers['children']),
      'infants': count(passengers['infants']),
      'smallBags': count(luggage['carriers20Inch']),
      'largeBags': count(luggage['carriers24InchPlus']),
      'golfBags': count(luggage['golfBags']),
      'flight': flightNumber.isEmpty
          ? ''
          : '${thai ? '✈️ เที่ยวบิน' : '✈️ 항공편'}: $flightNumber',
      'nameSign': options['nameSign'] == true
          ? (thai ? '🪧 ป้ายชื่อ: รวมในรายการจอง' : '🪧 피켓: 예약에 포함')
          : '',
      'driver': value(_text(assignment['driverDisplayName'])),
      'plate': value(_text(vehicle['plateNumber'])),
    };
    // Single-pass replacement: user-supplied place names are never templates.
    return l10n
        .t('admin_driver_check_context')
        .replaceAllMapped(
          RegExp(r'\{([A-Za-z]+)\}'),
          (m) => values[m.group(1)] ?? m.group(0)!,
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  return [
    AdminDriverCheckMessage(
      id: 'brief',
      titleKey: 'admin_driver_check_handoff',
      thai: render('th'),
      korean: render('ko'),
    ),
  ];
}
