import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/pwa/driver_pwa_install_prompt.dart';
import 'l10n/app_localizations.dart';
import 'features/booking/pages/guest_booking_lookup_page.dart';
import 'features/driver_application/pages/driver_application_form_page.dart';
import 'features/driver/pages/driver_login_page.dart';
import 'features/driver/pages/driver_shell_page.dart';
import 'features/driver_settlement/pages/driver_settlement_list_page.dart';
import 'features/driver_settlement/services/driver_settlement_api_service.dart';
import 'features/driver_settlement/utils/e2e_receipt_file_picker.dart'
    if (dart.library.html) 'features/driver_settlement/utils/e2e_receipt_file_picker_web.dart';
import 'features/support/pages/customer_support_page.dart';
import 'providers/booking_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'screens/admin/admin_screen.dart';

const bool _enableDriverE2ERoutes = bool.fromEnvironment(
  'TRIDE_ENABLE_E2E_ROUTES',
);
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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
      navigatorKey: _navigatorKey,
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
        '/': (_) => const HomeScreen(),
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
        if (_enableDriverE2ERoutes)
          '/driver/e2e/settlement-detail': (_) => DriverPwaInstallPromptHost(
            child: DriverE2ESettlementDetailRoute(uri: Uri.base),
          ),
      },
      onGenerateRoute: buildDriverE2ERoute,
      onGenerateInitialRoutes: (initialRoute) {
        final e2eRoute = buildDriverE2ERoute(RouteSettings(name: initialRoute));
        if (e2eRoute != null) return [e2eRoute];

        final navigator = _navigatorKey.currentState;
        if (navigator != null) {
          return Navigator.defaultGenerateInitialRoutes(
            navigator,
            initialRoute,
          );
        }
        return [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: initialRoute),
            builder: (_) => const HomeScreen(),
          ),
        ];
      },
    );
  }
}

@visibleForTesting
bool driverE2ESettlementRouteEnabled({bool enabled = _enableDriverE2ERoutes}) {
  return enabled;
}

@visibleForTesting
Route<dynamic>? buildDriverE2ERoute(
  RouteSettings settings, {
  bool enabled = _enableDriverE2ERoutes,
}) {
  if (!driverE2ESettlementRouteEnabled(enabled: enabled)) return null;

  final uri = Uri.tryParse(settings.name ?? '');
  if (uri?.path == '/driver/e2e/settlement-detail') {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => DriverPwaInstallPromptHost(
        child: DriverE2ESettlementDetailRoute(uri: uri!),
      ),
    );
  }
  return null;
}

@visibleForTesting
String? driverE2ESettlementBookingNumber(Uri uri) {
  final bookingNumber = uri.queryParameters['bookingNumber']?.trim();
  if (bookingNumber == null || bookingNumber.isEmpty) return null;
  if (!RegExp(r'^TX[0-9A-Za-z_-]+$').hasMatch(bookingNumber)) return null;
  return bookingNumber;
}

@visibleForTesting
class DriverE2ESettlementDetailRoute extends StatelessWidget {
  const DriverE2ESettlementDetailRoute({
    super.key,
    required this.uri,
    this.routesEnabled = _enableDriverE2ERoutes,
  });

  final Uri uri;
  final bool routesEnabled;

  static const _driverTokenKey = 'driver_access_token';

  Future<bool> _hasDriverSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_driverTokenKey);
    return token != null && token.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final bookingNumber = driverE2ESettlementBookingNumber(uri);
    if (!driverE2ESettlementRouteEnabled(enabled: routesEnabled)) {
      return const _DriverE2ERouteBlockedPage(
        message: 'Driver E2E routes are disabled',
      );
    }
    if (bookingNumber == null) {
      return const _DriverE2ERouteBlockedPage(
        message: 'Driver E2E settlement booking number is required',
      );
    }
    return FutureBuilder<bool>(
      future: _hasDriverSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != true) {
          return const DriverLoginPage();
        }
        return DriverSettlementDetailPage(
          bookingNumber: bookingNumber,
          api: const DriverSettlementApiService(),
          receiptPicker: kIsWeb ? e2eWebReceiptFilePicker() : null,
        );
      },
    );
  }
}

class _DriverE2ERouteBlockedPage extends StatelessWidget {
  const _DriverE2ERouteBlockedPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T-Ride')),
      body: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}
