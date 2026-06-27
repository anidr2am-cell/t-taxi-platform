import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../services/driver_api_service.dart';
import '../driver_auth.dart';
import 'driver_jobs_page.dart';
import 'driver_notifications_page.dart';
import 'driver_profile_page.dart';

/// Mobile-first driver shell: Jobs (default), Notifications, Settlement, Profile.
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = [
      DriverJobsPage(api: _api),
      DriverNotificationsPage(api: _api),
      DriverSettlementListPage(api: null),
      DriverProfilePage(api: _api),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.work_outline),
            selectedIcon: const Icon(Icons.work),
            label: l10n.t('driver_nav_jobs'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: l10n.t('driver_nav_notifications'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l10n.t('driver_nav_settlement'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.t('driver_nav_profile'),
          ),
        ],
      ),
    );
  }
}
