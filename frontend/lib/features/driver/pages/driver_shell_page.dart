import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../services/driver_api_service.dart';
import '../widgets/driver_status_control.dart';
import 'driver_account_page.dart';
import 'driver_jobs_page.dart';
import 'driver_today_page.dart';

/// Mobile-first driver shell: Home, Jobs, Settlement, Profile.
class DriverShellPage extends StatefulWidget {
  const DriverShellPage({super.key, this.api, this.settlementApi});

  final DriverApiService? api;
  final DriverSettlementApiService? settlementApi;

  @override
  State<DriverShellPage> createState() => _DriverShellPageState();
}

class _DriverShellPageState extends State<DriverShellPage> {
  int _index = 0;
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late final DriverSettlementApiService _settlementApi =
      widget.settlementApi ?? const DriverSettlementApiService();
  int _settlementBadge = 0;

  @override
  void initState() {
    super.initState();
    _ensureAuthenticated();
    _refreshSettlementBadge();
  }

  Future<void> _ensureAuthenticated() async {
    final token = await _api.getSavedToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      driverRedirectToLogin(context);
    }
  }

  void _refreshSession() {
    _refreshSettlementBadge();
    setState(() {});
  }

  Future<void> _refreshSettlementBadge() async {
    try {
      final items = await _settlementApi.listSettlements();
      if (!mounted) return;
      setState(() {
        _settlementBadge = DriverUx.countPendingSettlements(items);
      });
    } catch (_) {}
  }

  void _switchTab(int index) {
    setState(() => _index = index);
  }

  String _titleForIndex(AppLocalizations l10n) {
    return switch (_index) {
      0 => l10n.t('driver_nav_home'),
      1 => l10n.t('driver_nav_jobs'),
      2 => l10n.t('driver_nav_settlement'),
      _ => l10n.t('driver_nav_profile'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = [
      DriverTodayPage(
        api: _api,
        settlementApi: _settlementApi,
        onSessionChanged: _refreshSession,
        onNavigateToJobs: () => _switchTab(1),
        onNavigateToSettlement: () => _switchTab(2),
      ),
      DriverJobsPage(api: _api, onSessionChanged: _refreshSession),
      DriverSettlementListPage(api: _settlementApi),
      DriverAccountPage(
        api: _api,
        settlementApi: _settlementApi,
        onStatusChanged: _refreshSession,
        showAppBar: false,
      ),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: Text(_titleForIndex(l10n))),
        body: Column(
          children: [
            DriverStatusControl(api: _api, onStatusChanged: _refreshSession),
            Expanded(child: pages[_index]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          height: 72,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: _switchTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.t('driver_nav_home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.work_outline),
              selectedIcon: const Icon(Icons.work),
              label: l10n.t('driver_nav_jobs'),
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _settlementBadge > 0,
                label: Text('$_settlementBadge'),
                child: const Icon(Icons.payments_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _settlementBadge > 0,
                label: Text('$_settlementBadge'),
                child: const Icon(Icons.payments),
              ),
              label: l10n.t('driver_nav_settlement'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.t('driver_nav_profile'),
            ),
          ],
        ),
      ),
    );
  }
}
