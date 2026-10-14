import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/utils/pricing_location_params.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';

void main() {
  const bkk = LocationOption(
    id: 'bkk',
    displayName: 'BKK',
    kind: LocationKind.airport,
    code: 'BKK',
  );
  for (final name in [
    'Don Mueang International Airport (DMK)',
    '돈므앙 국제공항',
    'ท่าอากาศยานดอนเมือง',
    'ドンムアン空港',
    '廊曼国际机场',
  ]) {
    test('airport destination beats city region: $name', () {
      final dest = LocationOption(
        id: 'dmk',
        displayName: name,
        name: name,
        kind: LocationKind.place,
        code: 'BANGKOK',
        region: 'Bangkok',
      );
      final p = pricingLocationParams(
        service: BookingServiceType.airportPickup,
        origin: bkk,
        destination: dest,
      );
      expect(p['destinationLocationCode'], 'DMK');
      expect(p['destinationRegion'], isNull);
    });
  }
  test('airport hotel remains a city destination', () {
    const hotel = LocationOption(
      id: 'hotel',
      displayName: 'Novotel Bangkok Suvarnabhumi Airport Hotel',
      name: 'Novotel Bangkok Suvarnabhumi Airport Hotel',
      kind: LocationKind.place,
      code: 'BANGKOK',
    );
    expect(airportDestinationCodeFromOption(hotel), isNull);
    expect(
      pricingLocationParams(
        service: BookingServiceType.airportPickup,
        origin: bkk,
        destination: hotel,
      )['destinationLocationCode'],
      'BANGKOK',
    );
  });
  test('reverse airport route uses BKK destination', () {
    const dmk = LocationOption(
      id: 'dmk',
      displayName: 'DMK',
      kind: LocationKind.airport,
      code: 'DMK',
    );
    const dest = LocationOption(
      id: 'bkk-place',
      displayName: 'Suvarnabhumi Airport (BKK)',
      name: 'Suvarnabhumi Airport (BKK)',
      kind: LocationKind.place,
      code: 'BANGKOK',
    );
    final p = pricingLocationParams(
      service: BookingServiceType.airportPickup,
      origin: dmk,
      destination: dest,
    );
    expect(p['originAirportIata'], 'DMK');
    expect(p['destinationLocationCode'], 'BKK');
  });
}
