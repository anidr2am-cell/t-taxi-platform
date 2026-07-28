import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tride_driver/core/locale/locale_controller.dart';
import 'package:tride_driver/core/locale/locale_preferences.dart';
import 'package:tride_driver/l10n/app_localizations.dart';

Future<LocaleController> createTestLocaleController({
  String localeCode = 'ko',
}) async {
  SharedPreferences.setMockInitialValues({
    LocalePreferences.storageKey: localeCode,
  });
  final prefs = await SharedPreferences.getInstance();
  return LocaleController(LocalePreferences(prefs));
}

Widget localizedMaterialApp({
  Widget? home,
  Locale locale = const Locale('ko'),
  ThemeData? theme,
  String? initialRoute,
  Map<String, WidgetBuilder>? routes,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: theme,
    home: initialRoute == null ? home : null,
    initialRoute: initialRoute,
    routes: routes ?? const {},
  );
}

Future<void> pumpLocalizedWidget(
  WidgetTester tester, {
  required Widget home,
  Locale locale = const Locale('ko'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    localizedMaterialApp(home: home, locale: locale, theme: theme),
  );
  await tester.pumpAndSettle();
}
