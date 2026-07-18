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

const bool _enableE2ERoutes = bool.fromEnvironment('TRIDE_ENABLE_E2E_ROUTES');

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
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri?.path == '/admin/e2e/settlement-detail') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => AdminE2ESettlementDetailRoute(uri: uri!),
          );
        }
        return null;
      },
      home: const HomeScreen(),
    );
  }
}

@visibleForTesting
bool adminE2ERoutesEnabled({bool enabled = _enableE2ERoutes}) {
  return enabled;
}

@visibleForTesting
String? adminE2ESettlementBookingNumber(Uri uri) {
  final bookingNumber = uri.queryParameters['bookingNumber']?.trim();
  if (bookingNumber == null || bookingNumber.isEmpty) return null;
  if (!RegExp(r'^TX[0-9A-Za-z_-]+$').hasMatch(bookingNumber)) return null;
  return bookingNumber;
}

@visibleForTesting
class AdminE2ESettlementDetailRoute extends StatelessWidget {
  const AdminE2ESettlementDetailRoute({
    super.key,
    required this.uri,
    this.routesEnabled = _enableE2ERoutes,
  });

  final Uri uri;
  final bool routesEnabled;

  @override
  Widget build(BuildContext context) {
    final bookingNumber = adminE2ESettlementBookingNumber(uri);
    if (!adminE2ERoutesEnabled(enabled: routesEnabled)) {
      return const _AdminE2ERouteBlockedPage(
        message: 'Admin E2E routes are disabled',
      );
    }
    if (bookingNumber == null) {
      return const _AdminE2ERouteBlockedPage(
        message: 'Admin E2E settlement booking number is required',
      );
    }
    return Material(
      child: AdminAuthGate(
        child: AdminSettlementDetailPage(
          bookingNumber: bookingNumber,
          api: const AdminSettlementApiService(),
          onChanged: () {},
        ),
      ),
    );
  }
}

class _AdminE2ERouteBlockedPage extends StatelessWidget {
  const _AdminE2ERouteBlockedPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T-Ride')),
      body: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}
