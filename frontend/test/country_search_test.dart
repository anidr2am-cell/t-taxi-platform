import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/country_option.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test(
    'country aliases find South Korea and selected values normalize to KR',
    () {
      for (final query in [
        'korea',
        'south korea',
        '한국',
        '대한민국',
        'เกาหลี',
        'เกาหลีใต้',
      ]) {
        final matches = CountryCatalog.search(query).toList();
        expect(matches, isNotEmpty, reason: query);
        expect(matches.first.code, 'KR', reason: query);
      }
    },
  );

  test(
    'ISO country codes display in the current locale and free text survives',
    () {
      expect(CountryCatalog.displayName('KR', AppLocalizations('ko')), '대한민국');
      expect(
        CountryCatalog.displayName('KR', AppLocalizations('en')),
        'South Korea',
      );
      expect(
        CountryCatalog.displayName('KR', AppLocalizations('th')),
        'เกาหลีใต้',
      );
      expect(
        CountryCatalog.displayName('korea', AppLocalizations('en')),
        'korea',
      );
      expect(CountryCatalog.displayName('', AppLocalizations('en')), '');
    },
  );
}
