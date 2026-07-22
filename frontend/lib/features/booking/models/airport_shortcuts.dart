import 'location_option.dart';
import 'thailand_registered_airports.dart';

/// Static Thailand airport shortcuts — no Google API calls.
///
/// Registered staging airports (BKK/DMK/CNX/HKT) come from
/// [ThailandRegisteredAirports] so Flutter and SQL stay aligned.
/// Google Place IDs are intentionally omitted until verified.
class AirportShortcuts {
  static List<LocationOption> get thailandAirports => all;

  static const List<LocationOption> all = [
    ...ThailandRegisteredAirports.all,
    LocationOption(
      id: 'airport:UTP',
      displayName: 'UTP — U-Tapao Rayong-Pattaya International Airport',
      kind: LocationKind.airport,
      code: 'UTP',
      name: 'UTP — U-Tapao Rayong-Pattaya International Airport',
      address:
          'UTP U-Tapao Rayong-Pattaya International Airport, Rayong, Thailand',
      latitude: 12.679944,
      longitude: 101.005028,
    ),
  ];
}
