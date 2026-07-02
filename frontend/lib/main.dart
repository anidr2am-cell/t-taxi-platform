import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'features/booking/pages/guest_booking_lookup_page.dart';
import 'features/driver/pages/driver_login_page.dart';
import 'features/driver/pages/driver_shell_page.dart';
import 'providers/booking_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'screens/admin/admin_screen.dart';

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
      title: 'T-Ride',
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
        '/admin': (_) => const AdminScreen(),
        '/booking/lookup': (_) => const GuestBookingLookupPage(),
        '/driver': (_) => const DriverLoginPage(),
        '/driver/home': (_) => const DriverShellPage(),
        '/driver/jobs': (_) => const DriverShellPage(),
      },
      home: const HomeScreen(),
    );
  }
}
