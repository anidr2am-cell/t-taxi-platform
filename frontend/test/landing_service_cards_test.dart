import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/landing/widgets/landing_service_cards.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrap({
  required Widget child,
  double width = 360,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate(locale.languageCode),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LandingServiceCards', () {
    testWidgets('shows four compact tiles in one row at 360px without overflow', (tester) async {
      await tester.pumpWidget(
        _wrap(child: LandingServiceCards(onBook: () {})),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final serviceRow = tester.widget<Row>(find.byKey(const Key('landing_service_row')));
      expect(serviceRow.children.whereType<Expanded>().length, 4);
      expect(find.text('Airport Pickup'), findsOneWidget);
      expect(find.text('Airport Dropoff'), findsOneWidget);
      expect(find.text('City Transfer'), findsOneWidget);
      expect(find.text('Golf Transfer'), findsOneWidget);
    });

    testWidgets('tap selects service and triggers booking callback', (tester) async {
      var booked = false;

      await tester.pumpWidget(
        _wrap(child: LandingServiceCards(onBook: () => booked = true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('City Transfer'));
      await tester.pumpAndSettle();

      expect(booked, isTrue);
    });

    testWidgets('each service tile opens booking flow', (tester) async {
      for (final type in BookingServiceType.values) {
        var booked = false;
        final l10n = AppLocalizations('en');

        await tester.pumpWidget(
          _wrap(child: LandingServiceCards(onBook: () => booked = true)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.t(type.labelKey)));
        await tester.pumpAndSettle();

        expect(booked, isTrue, reason: 'Expected onBook for ${type.name}');
      }
    });

    testWidgets('labels render across supported locales without overflow', (tester) async {
      for (final code in AppLocalizations.supportedLanguages) {
        await tester.pumpWidget(
          _wrap(
            locale: Locale(code),
            child: LandingServiceCards(onBook: () {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Overflow for locale $code');
        expect(find.byKey(const Key('landing_service_row')), findsOneWidget);
      }
    });

    testWidgets('compact tiles meet minimum touch height', (tester) async {
      await tester.pumpWidget(
        _wrap(child: LandingServiceCards(onBook: () {})),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byType(ConstrainedBox).first;
      final constrainedBox = tester.widget<ConstrainedBox>(tileFinder);
      expect(constrainedBox.constraints.minHeight, greaterThanOrEqualTo(44));
    });
  });
}
