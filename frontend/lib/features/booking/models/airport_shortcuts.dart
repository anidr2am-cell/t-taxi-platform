import 'location_option.dart';

/// Static Thailand airport shortcuts — no Google API calls.
/// All entries are Thailand airports (see [LocationOption.address] / id prefix `airport:`).
class AirportShortcuts {
  static List<LocationOption> get thailandAirports => all;

  static const List<LocationOption> all = [
    LocationOption(
      id: 'airport:BKK',
      displayName: 'Suvarnabhumi Airport (BKK)',
      kind: LocationKind.airport,
      code: 'BKK',
      name: 'Suvarnabhumi Airport',
      address: 'Bangkok, Thailand',
    ),
    LocationOption(
      id: 'airport:DMK',
      displayName: 'Don Mueang Airport (DMK)',
      kind: LocationKind.airport,
      code: 'DMK',
      name: 'Don Mueang International Airport',
      address: 'Bangkok, Thailand',
    ),
    LocationOption(
      id: 'airport:HKT',
      displayName: 'Phuket Airport (HKT)',
      kind: LocationKind.airport,
      code: 'HKT',
      name: 'Phuket International Airport',
      address: 'Phuket, Thailand',
    ),
    LocationOption(
      id: 'airport:CNX',
      displayName: 'Chiang Mai Airport (CNX)',
      kind: LocationKind.airport,
      code: 'CNX',
      name: 'Chiang Mai International Airport',
      address: 'Chiang Mai, Thailand',
    ),
    LocationOption(
      id: 'airport:UTP',
      displayName: 'U-Tapao Airport (UTP)',
      kind: LocationKind.airport,
      code: 'UTP',
      name: 'U-Tapao Rayong-Pattaya International Airport',
      address: 'Rayong, Thailand',
    ),
  ];
}
