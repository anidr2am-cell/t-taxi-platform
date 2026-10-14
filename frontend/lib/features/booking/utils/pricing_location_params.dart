import '../models/location_option.dart';
import '../models/service_type_option.dart';

const _knownAirportIataByText = <String, String>{
  'BKK': 'BKK',
  'SUVARNABHUMI': 'BKK',
  'สุวรรณภูมิ': 'BKK',
  'スワンナプーム': 'BKK',
  '素万那普': 'BKK',
  'DMK': 'DMK',
  'DON MUEANG': 'DMK',
  'DON MUANG': 'DMK',
  'ดอนเมือง': 'DMK',
  'ドンムアン': 'DMK',
  '廊曼': 'DMK',
  'HKT': 'HKT',
  'PHUKET AIRPORT': 'HKT',
  'CNX': 'CNX',
  'CHIANG MAI AIRPORT': 'CNX',
  'UTP': 'UTP',
  'U-TAPAO': 'UTP',
  'UTAPAO': 'UTP',
};

const _knownLocationCodeByText = <String, String>{
  'PATTAYA': 'PATTAYA',
  '파타야': 'PATTAYA',
  'เมืองพัทยา': 'PATTAYA',
  'พัทยา': 'PATTAYA',
  '芭堤雅': 'PATTAYA',
  'パタヤ': 'PATTAYA',
  'パッタヤ': 'PATTAYA',
  'BANGKOK': 'BANGKOK',
  '방콕': 'BANGKOK',
  'กรุงเทพ': 'BANGKOK',
  'กรุงเทพมหานคร': 'BANGKOK',
  '曼谷': 'BANGKOK',
  'バンコク': 'BANGKOK',
  'HUA_HIN': 'HUA_HIN',
  'HUAHIN': 'HUA_HIN',
  'หัวหิน': 'HUA_HIN',
  '华欣': 'HUA_HIN',
  'フアヒン': 'HUA_HIN',
  '후아힌': 'HUA_HIN',
  'RAYONG': 'RAYONG',
  'ระยอง': 'RAYONG',
  '罗勇': 'RAYONG',
  'ラヨン': 'RAYONG',
  '라용': 'RAYONG',
};

Map<String, String?> pricingLocationParams({
  required BookingServiceType? service,
  required LocationOption? origin,
  required LocationOption? destination,
}) {
  String? originAirportIata;
  String? destinationRegion;
  String? originLocationCode;
  String? destinationLocationCode;

  if (service == BookingServiceType.airportPickup) {
    originAirportIata = airportIataFromOption(origin);
    destinationLocationCode =
        airportDestinationCodeFromOption(destination) ??
        internalLocationCodeFromOption(destination);
    destinationRegion = destinationLocationCode == null
        ? regionFromLocation(destination)
        : null;
  } else if (service == BookingServiceType.airportDropoff) {
    originLocationCode =
        internalLocationCodeFromOption(origin) ?? regionFromLocation(origin);
    final destinationAirportIata = airportIataFromOption(destination);
    destinationLocationCode =
        internalLocationCodeFromOption(destination) ?? destinationAirportIata;
    destinationRegion = destinationLocationCode == null
        ? regionFromLocation(destination)
        : null;
  } else if (service == BookingServiceType.cityTransfer ||
      service == BookingServiceType.golfTransfer) {
    originAirportIata = airportIataFromOption(origin);
    originLocationCode = originAirportIata == null
        ? (internalLocationCodeFromOption(origin) ?? regionFromLocation(origin))
        : null;
    destinationLocationCode = internalLocationCodeFromOption(destination);
    destinationRegion = destinationLocationCode == null
        ? regionFromLocation(destination ?? origin)
        : null;
  }

  return {
    'originAirportIata': originAirportIata,
    'destinationRegion': destinationRegion,
    'originLocationCode': originLocationCode,
    'destinationLocationCode': destinationLocationCode,
  };
}

String? regionFromLocation(LocationOption? location) {
  if (location == null) return null;
  if (location.region?.isNotEmpty == true) return location.region;
  if (location.code?.isNotEmpty == true &&
      location.kind != LocationKind.place &&
      location.kind != LocationKind.golf) {
    return location.code;
  }
  if (location.name?.isNotEmpty == true) return location.name;
  if (location.address?.isNotEmpty == true) {
    return location.address!.split(',').first.trim();
  }
  final name = location.displayName.split(',').first.trim();
  return name.isEmpty ? null : name;
}

String? airportIataFromOption(LocationOption? location) {
  if (location == null) return null;
  final code = location.code?.trim().toUpperCase();
  if (code != null && _knownAirportIataByText.containsValue(code)) return code;
  final text = [
    location.code,
    location.name,
    location.displayName,
    location.address,
  ].whereType<String>().join(' ').toUpperCase();
  for (final entry in _knownAirportIataByText.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return null;
}

String? internalLocationCodeFromOption(LocationOption? location) {
  if (location == null) return null;
  final code = location.code?.trim().toUpperCase();
  if (code != null &&
      code.isNotEmpty &&
      _knownLocationCodeByText.containsValue(code)) {
    return code;
  }
  if (code != null && code.isNotEmpty && location.kind != LocationKind.place) {
    return code;
  }
  final text = [
    location.region,
    location.name,
    location.displayName,
    location.address,
  ].whereType<String>().join(' ').toUpperCase();
  for (final entry in _knownLocationCodeByText.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return null;
}

// Resolve an airport selected as a Places result before its city/address region.
// Match the place name exactly after removing airport descriptors, never an
// airport name embedded in a hotel name or address.
String? airportDestinationCodeFromOption(LocationOption? location) {
  if (location == null) return null;
  if (location.kind == LocationKind.airport)
    return airportIataFromOption(location);
  final explicit = location.code?.trim().toUpperCase();
  if (_knownAirportIataByText.containsValue(explicit)) return explicit;
  var name = (location.name ?? location.displayName).trim().toUpperCase();
  name = name.replaceAll(RegExp(r'\((BKK|DMK|HKT|CNX|UTP)\)'), '');
  name = name.replaceAll(
    RegExp(
      r'INTERNATIONAL|AIRPORT|국제|공항|國際|国际|機場|机场|国際|空港|ท่าอากาศยาน|สนามบิน|นานาชาติ',
    ),
    '',
  );
  String compact(String value) => value.replaceAll(RegExp(r'[\s_\-]'), '');
  final aliases = <String, String>{
    ..._knownAirportIataByText,
    '수완나품': 'BKK',
    '돈므앙': 'DMK',
  };
  for (final entry in aliases.entries) {
    if (compact(name) == compact(entry.key.toUpperCase())) return entry.value;
  }
  return null;
}
