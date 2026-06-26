import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'features/driver/pages/driver_jobs_page.dart';
import 'features/driver/pages/driver_login_page.dart';
import 'providers/booking_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleState()),
        ChangeNotifierProvider(create: (_) => BookingState()),
      ],
      child: const TTaxiApp(),
    ),
  );
}

class TTaxiApp extends StatelessWidget {
  const TTaxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleState>();

    return MaterialApp(
      title: 'TTaxi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: Locale(locale.languageCode),
      supportedLocales: AppLocalizations.supportedLanguages
          .map((code) => Locale(code))
          .toList(),
      localizationsDelegates: [
        AppLocalizationsDelegate(locale.languageCode),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routes: {
        '/driver': (_) => const DriverLoginPage(),
        '/driver/jobs': (_) => const DriverJobsPage(),
      },
      home: const HomeScreen(),
    );
  }
}
