import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/dispatch/data/airport_label_resolver.dart';

void main() {
  test('matches IATA-only labels like the driver web', () {
    expect(
      AirportLabelResolver.displayLabelFor('BKK'),
      'BKK — Suvarnabhumi Airport',
    );
    expect(
      AirportLabelResolver.displayLabelFor('dmk, Thailand'),
      'DMK — Don Mueang International Airport',
    );
  });

  test('matches official airport names', () {
    expect(
      AirportLabelResolver.displayLabelFor(
        'Arrivals at Chiang Mai International Airport',
      ),
      'CNX — Chiang Mai International Airport',
    );
  });

  test('matches code plus airport and labeled forms', () {
    expect(
      AirportLabelResolver.displayLabelFor('HKT Airport terminal'),
      'HKT — Phuket International Airport',
    );
    expect(
      AirportLabelResolver.displayLabelFor(
        'UTP - U-Tapao Rayong-Pattaya International Airport',
      ),
      'UTP — U-Tapao Rayong-Pattaya International Airport',
    );
  });

  test('matches compact airport identity', () {
    expect(
      AirportLabelResolver.displayLabelFor(
        'BKKSUVARNABHUMIAIRPORT passenger terminal',
      ),
      'BKK — Suvarnabhumi Airport',
    );
  });

  test('does not mistake unrelated code text for an airport', () {
    expect(
      AirportLabelResolver.displayLabelFor('BKK Riverside Hotel'),
      'BKK Riverside Hotel',
    );
  });

  test('keeps ordinary addresses unchanged and trimmed', () {
    expect(
      AirportLabelResolver.displayLabelFor('  123 Sukhumvit Road  '),
      '123 Sukhumvit Road',
    );
  });

  test('uses the same city and IATA ambiguity patterns', () {
    expect(AirportLabelResolver.isAmbiguousCityOrIataOnly('Bangkok'), isTrue);
    expect(AirportLabelResolver.isAmbiguousCityOrIataOnly('CNX, TH'), isTrue);
    expect(
      AirportLabelResolver.isAmbiguousCityOrIataOnly('Pattaya Hotel'),
      isFalse,
    );
  });
}
