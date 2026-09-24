import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../features/admin_dispatch/pages/admin_booking_detail_page.dart';
import '../features/admin_dispatch/pages/admin_manual_booking_create_page.dart';
import '../features/admin_dispatch/services/admin_dispatch_api_service.dart';
import '../features/booking/services/flight_lookup_api_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Local QA entry — run with:
/// flutter run -d chrome -t lib/qa/admin_manual_qa_main.dart
///   --dart-define=API_BASE_URL=http://127.0.0.1:3099
///   --dart-define=APP_ENV=development
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminManualQaApp());
}

class AdminManualQaApp extends StatelessWidget {
  const AdminManualQaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Manual QA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLanguages
          .map((code) => Locale(code))
          .toList(),
      localizationsDelegates: [
        AppLocalizationsDelegate('ko'),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AdminManualQaHome(),
    );
  }
}

/// Mirrors [AdminScreen] body for the manual-call tab: themed [Scaffold] + [AppBar].
class AdminManualQaOperationalShell extends StatelessWidget {
  const AdminManualQaOperationalShell({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

class AdminManualQaHome extends StatefulWidget {
  const AdminManualQaHome({super.key});

  @override
  State<AdminManualQaHome> createState() => _AdminManualQaHomeState();
}

class _AdminManualQaHomeState extends State<AdminManualQaHome> {
  late final AdminDispatchApiService _dispatchApi;
  late final FlightLookupApiService _flightLookupApi;
  String? _bootstrapError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final base = AppConfig.apiBaseUrl;
    _dispatchApi = AdminDispatchApiService(baseUrl: base);
    _flightLookupApi = FlightLookupApiService.test(
      client: http.Client(),
      baseUrl: base,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _dispatchApi.login(
        email: 'qa-admin@example.test',
        password: 'qa-local-only',
      );
      if (!mounted) return;
      setState(() {
        _ready = true;
        _bootstrapError = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _bootstrapError = '$err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Manual QA')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Mock login failed. Start mock server:\n'
              'node frontend/qa/mock_admin_api_server.mjs\n\n'
              'Error: $_bootstrapError\n'
              'API_BASE_URL=${AppConfig.apiBaseUrl}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin Manual QA (local mock)'),
            Text(
              AppConfig.apiBaseUrl,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Create manual call'),
            subtitle: const Text('Input screen — luggage, flight, golf'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openManualCallPage(context, editBookingNumber: null),
          ),
          ListTile(
            title: const Text('Edit TX202609240001'),
            subtitle: const Text('Sparse string coords fixture'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openManualCallPage(
              context,
              editBookingNumber: 'TX202609240001',
            ),
          ),
          ListTile(
            title: const Text('Dispatch detail — assign success'),
            subtitle: const Text(
              'TX202609240001 · product assign API + success snackbar',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBookingDetail(context, 'TX202609240001'),
          ),
          ListTile(
            title: const Text('Dispatch detail — assign API conflict'),
            subtitle: const Text(
              'TX202609240003 · driver 199 eligible in list, 409 on submit',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBookingDetail(context, 'TX202609240003'),
          ),
        ],
      ),
    );
  }

  void _openManualCallPage(
    BuildContext context, {
    required String? editBookingNumber,
  }) {
    final l10n = context.l10n;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminManualQaOperationalShell(
          title: l10n.t('admin_manual_booking_menu'),
          child: AdminManualBookingCreatePage(
            dispatchApi: _dispatchApi,
            flightLookupApi: _flightLookupApi,
            editBookingNumber: editBookingNumber,
          ),
        ),
      ),
    );
  }

  void _openBookingDetail(BuildContext context, String bookingNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _dispatchApi,
          onChanged: () {},
        ),
      ),
    );
  }
}
