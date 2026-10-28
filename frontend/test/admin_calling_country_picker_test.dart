import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/models/admin_calling_codes.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_calling_country_picker.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget app(String language) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLanguages
      .map(Locale.new)
      .toList(),
  localizationsDelegates: [
    AppLocalizationsDelegate(language),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: const _Harness(),
);

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  AdminCallingCountry selected = adminCallingCountries.firstWhere(
    (c) => c.code == 'TH',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('open'),
        onPressed: () async {
          final result = await showAdminCallingCountryPicker(
            context,
            selectedCountryCode: selected.code,
          );
          if (result != null) setState(() => selected = result);
        },
        child: Text(selected.label(context.l10n.languageCode)),
      ),
    ),
  );
}

void main() {
  test(
    '245 countries retain all 206 calling codes and five translated names',
    () {
      expect(adminCallingCountries.length, 245);
      expect(adminCallingCountries.map((c) => c.code).toSet().length, 245);
      expect(adminCallingCodes.length, 206);
      for (final country in adminCallingCountries) {
        for (final language in AppLocalizations.supportedLanguages) {
          expect(country.names[language], isNotEmpty);
        }
      }
      expect(
        adminCallingCountries
            .where((c) => c.dialCode == '+1')
            .map((c) => c.code),
        containsAll(['US', 'CA']),
      );
      for (final query in [
        '한국',
        'Korea',
        'เกาหลีใต้',
        '韓国',
        '韩国',
        'KR',
        '+82',
        '82',
      ]) {
        expect(
          adminCallingCountries
              .where((c) => c.matches(query))
              .map((c) => c.code),
          contains('KR'),
        );
      }
    },
  );

  for (final language in AppLocalizations.supportedLanguages) {
    testWidgets('country search and long names fit 375px in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(language));
        await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizations(language).t('admin_phone_country_title')),
        findsOneWidget,
      );
      final search = find.byKey(const Key('adminCallingCountrySearch'));
      await tester.enterText(search, 'Korea');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('adminCallingCountry-KR')),
        findsOneWidget,
      );
      await tester.enterText(search, 'United Arab Emirates');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.enterText(search, 'zzzz-no-match');
      await tester.pump();
      expect(
        find.text(AppLocalizations(language).t('admin_phone_country_empty')),
        findsOneWidget,
      );
      await tester.enterText(search, '+998');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('adminCallingCountry-UZ')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          adminCallingCountries
              .firstWhere((c) => c.code == 'UZ')
              .label(language),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'shared code preserves selected country; cancel preserves selection',
    (tester) async {
      await tester.pumpWidget(app('ko'));
    await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('adminCallingCountrySearch')),
        '캐나다',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('adminCallingCountry-CA')));
      await tester.pumpAndSettle();
      expect(find.text('캐나다 (+1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('adminCallingCountrySearch')),
        'Canada',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('adminCallingCountry-CA')),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('adminCallingCountry-CA'))).selected, isTrue);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('캐나다 (+1)'), findsOneWidget);
    },
  );
}
