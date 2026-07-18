import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'core/pwa/driver_pwa_install_prompt.dart';
import 'l10n/app_localizations.dart';
import 'features/booking/pages/guest_booking_lookup_page.dart';
import 'features/driver_application/pages/driver_application_form_page.dart';
import 'features/driver/pages/driver_login_page.dart';
import 'features/driver/pages/driver_shell_page.dart';
import 'features/support/pages/customer_support_page.dart';
import 'features/admin/widgets/admin_auth_gate.dart';
import 'features/admin_settlement/pages/admin_settlement_queue_page.dart';
import 'features/admin_settlement/services/admin_settlement_api_service.dart';
import 'providers/booking_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'screens/admin/admin_screen.dart';

void main() {
  if (kIsWeb) {
    usePathUrlStrategy();
  }
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
    const enableE2eRoutes = bool.fromEnvironment('TRIDE_ENABLE_E2E_ROUTES');

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
        '/admin': (_) => const AdminScreen(initialTab: 1),
        '/booking/lookup': (_) =>
            const GuestBookingLookupPage(enableCustomerTools: true),
        '/driver': (_) =>
            const DriverPwaInstallPromptHost(child: DriverLoginPage()),
        '/driver/login': (_) =>
            const DriverPwaInstallPromptHost(child: DriverLoginPage()),
        '/driver/apply': (_) => const DriverApplicationFormPage(),
        '/driver/application-status': (_) => const DriverApplicationFormPage(),
        '/driver/home': (_) =>
            const DriverPwaInstallPromptHost(child: DriverShellPage()),
        '/driver/jobs': (_) =>
            const DriverPwaInstallPromptHost(child: DriverShellPage()),
        '/support': (_) => const CustomerSupportPage(),
      },
      onGenerateRoute: enableE2eRoutes
          ? (settings) {
              final uri = Uri.parse(settings.name ?? '');
              if (uri.path == '/admin/e2e/settlement-detail') {
                final bookingNumber = uri.queryParameters['bookingNumber'] ?? '';
                return MaterialPageRoute<void>(
                  builder: (_) => AdminAuthGate(
                    child: AdminSettlementDetailPage(
                      bookingNumber: bookingNumber,
                      api: const AdminSettlementApiService(),
                      onChanged: () {},
                    ),
                  ),
                );
              }
              return null;
            }
          : null,
      home: const HomeScreen(),
    );
  }
}
