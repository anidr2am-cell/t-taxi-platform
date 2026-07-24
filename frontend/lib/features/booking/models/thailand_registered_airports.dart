import 'location_option.dart';

/// Canonical registered Thailand airport locations for T-Ride (BKK/DMK/CNX/HKT).
///
/// Keep SQL seed/ops files in sync with these values:
/// - database/ops_airport_location_coords_fix.sql
/// - database/15_pricing_architecture.sql
/// - database/21_pricing_seed_repair.sql
/// - database/28_fare_table_image_seed.sql
///
/// Google Place IDs remain null until an operator verifies official Place IDs.
class ThailandRegisteredAirports {
  static const List<LocationOption> all = [
    LocationOption(
      id: 'airport:BKK',
      displayName: 'BKK — Suvarnabhumi Airport',
      kind: LocationKind.airport,
      code: 'BKK',
      name: 'BKK — Suvarnabhumi Airport',
      address:
          '999 Moo 1, Nong Prue, Bang Phli District, Samut Prakan 10540, Thailand',
      // AOT Suvarnabhumi contact-page Google Maps embed center (passenger-terminal area).
      // Source: https://suvarnabhumi.airportthai.co.th/contact-us
      // Not Bangkok city center; Samut Prakan. AIP ARP is runway-centered and not preferred
      // for driver curb navigation.
      latitude: 13.689999,
      longitude: 100.747924,
    ),
    LocationOption(
      id: 'airport:DMK',
      displayName: 'DMK — Don Mueang International Airport',
      kind: LocationKind.airport,
      code: 'DMK',
      name: 'DMK — Don Mueang International Airport',
      address:
          '222 Vibhavadi Rangsit Road, Sanambin Subdistrict, Don Mueang District, Bangkok 10210, Thailand',
      // AOT Don Mueang contact-page Google Maps embed center.
      // Source: https://donmueang.airportthai.co.th/contact-us
      latitude: 13.913260,
      longitude: 100.602010,
    ),
    LocationOption(
      id: 'airport:CNX',
      displayName: 'CNX — Chiang Mai International Airport',
      kind: LocationKind.airport,
      code: 'CNX',
      name: 'CNX — Chiang Mai International Airport',
      address:
          'Mahidol Road, Suthep Subdistrict, Mueang Chiang Mai District, Chiang Mai 50200, Thailand',
      // AOT-reported terminal-side coordinates (vehicle-accessible passenger terminal).
      // Corroborated by OSM passenger terminal ~18.768989, 98.968123.
      // Preferred over CAAT AIP ARP (runway center 18.771389, 98.962778) and over the
      // AOT contact embed viewport center (~98.9618, runway-west).
      latitude: 18.7679959,
      longitude: 98.968563,
    ),
    LocationOption(
      id: 'airport:HKT',
      displayName: 'HKT — Phuket International Airport',
      kind: LocationKind.airport,
      code: 'HKT',
      name: 'HKT — Phuket International Airport',
      address:
          '222 Moo 6, Mai Khao Subdistrict, Thalang District, Phuket 83110, Thailand',
      // AOT-reported international-terminal-side coordinates.
      // Corroborated by OSM "International Terminal" ~8.105883, 98.305702.
      // Preferred over CAAT AIP ARP (runway center 8.112500, 98.309167) and over the
      // AOT contact embed aerodrome-center viewport (~8.1111, 98.3043).
      latitude: 8.105401,
      longitude: 98.306054,
    ),
  ];

  static LocationOption? byCode(String? code) {
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final airport in all) {
      if (airport.code?.toUpperCase() == normalized) return airport;
    }
    return null;
  }
}
