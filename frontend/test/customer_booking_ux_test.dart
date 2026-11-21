import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/l10n/customer_traditional_chinese.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/services/recent_locations_storage.dart';
import 'package:frontend/features/booking/utils/booking_contact_preference.dart';
import 'package:frontend/features/booking/widgets/google_places_search_field.dart';

class _RecentPlaces implements RecentLocationsRepository {
  @override
  Future<void> add(LocationOption location) async {}
  @override
  Future<List<LocationOption>> load() async => List.generate(
    4,
    (i) => LocationOption(
      id: 'qa-$i',
      displayName: 'QA Place $i',
      kind: LocationKind.place,
    ),
  );
}

void main() {
  test(
    'Traditional Chinese stays distinct and defaults to Taiwan / official LINE',
    () {
      expect(AppLocalizations('zh-TW').t('airport_pickup'), '機場接機');
    expect(AppLocalizations('zh-TW').t('airport_shortcuts_origin'), contains('機場'));
    final locale = AppLocalizations.flutterLocale('zh-TW');
      expect(locale.languageCode, 'zh');
      expect(locale.scriptCode, 'Hant');
      expect(locale.countryCode, 'TW');
      expect(
        AppLocalizations.customerSupportedLanguages,
        containsAll(['zh', 'zh-TW']),
      );
      expect(BookingContactPreference.defaultDialCode('zh-TW'), '+886');
      expect(
        BookingContactPreference.defaultFor(languageCode: 'zh-TW'),
        'LINE',
      );
      expect(contactChannelOrderForLocale('ja').first, 'LINE');
      expect(contactChannelOrderForLocale('zh-TW').first, 'LINE');
      for (final entry in customerTraditionalChinese.entries) {
        expect(AppLocalizations('zh-TW').t(entry.key), entry.value);
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
      expect(
        AppLocalizations('zh-TW').t('ux_golf_help'),
        contains('車輛預約不代表開球時間已確認'),
      );
    },
  );

  testWidgets('search precedes two recent places and more expands the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GooglePlacesSearchField(
              label: 'Search',
              languageCode: 'en',
              recentLocationsStorage: RecentLocationsStorage(
                guestRepository: _RecentPlaces(),
              ),
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QA Place 0'), findsOneWidget);
    expect(find.text('QA Place 1'), findsOneWidget);
    expect(find.text('QA Place 2'), findsNothing);
    expect(
      tester.getTopLeft(find.byType(TextField)).dy,
      lessThan(tester.getTopLeft(find.text('QA Place 0')).dy),
    );
    await tester.tap(find.text(AppLocalizations('en').t('ux_more_places')));
    await tester.pumpAndSettle();
    expect(find.text('QA Place 3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    expect(find.text('QA Place 0'), findsNothing);
  });
}
