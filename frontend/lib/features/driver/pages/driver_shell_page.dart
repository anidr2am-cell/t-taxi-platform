import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../driver_auth.dart';
import '../services/driver_api_service.dart';
import 'driver_booking_detail_page.dart';
import 'driver_notifications_page.dart';
import 'driver_today_page.dart';
import 'driver_trip_history_page.dart';
import 'driver_account_page.dart';

/// Mobile-first driver shell: Today (default), Trip history, Notifications, Account.
class DriverShellPage extends StatefulWidget {
  const DriverShellPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverShellPage> createState() => _DriverShellPageState();
}

class _DriverShellPageState extends State<DriverShellPage> {
  int _index = 0;
  late final DriverApiService _api = widget.api ?? DriverApiService();

  @override
  void initState() {
    super.initState();
    _ensureAuthenticated();
  }

  Future<void> _ensureAuthenticated() async {
    final token = await _api.getSavedToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      driverRedirectToLogin(context);
    }
  }

  void _refreshSession() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = [
      DriverTodayPage(api: _api, onSessionChanged: _refreshSession),
      DriverTripHistoryPage(api: _api),
      DriverNotificationsPage(
        api: _api,
        detailPageBuilder: (bookingNumber) => DriverBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _api,
        ),
      ),
      DriverAccountPage(api: _api, onStatusChanged: _refreshSession),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.t('driver_nav_today'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.t('driver_nav_history'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: l10n.t('driver_nav_notifications'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.t('driver_nav_account'),
          ),
        ],
      ),
    );
  }
}
