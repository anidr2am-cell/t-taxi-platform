import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/firebase/fcm_token_service.dart';
import '../../../core/firebase/fcm_message_service.dart';
import '../../../core/locale/locale_controller.dart';
import '../../account/data/account_api.dart';
import '../../account/presentation/account_page.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/presentation/booking_list_screen.dart';
import '../../settlement/data/settlement_api.dart';
import '../../settlement/presentation/settlement_list_page.dart';
import '../../support/data/support_contact_api.dart';
import '../data/dispatch_repository.dart';
import '../data/driver_socket_service.dart';
import '../../../l10n/app_localizations.dart';
import 'open_calls_screen.dart';
import 'urgent_eta_dialog.dart';

class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({
    super.key,
    required this.bookingRepository,
    required this.dispatchRepository,
    required this.localeController,
    required this.onUnauthorized,
    required this.onLogout,
    this.accountApi,
    this.settlementApi,
    this.driverSocket,
    this.fcmTokenService,
    this.fcmMessageService,
    this.supportContactApi,
  });

  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final LocaleController localeController;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;
  final DriverSocketConnection? driverSocket;
  final AccountDataSource? accountApi;
  final SettlementDataSource? settlementApi;
  final FcmTokenService? fcmTokenService;
  final FcmMessageService? fcmMessageService;
  final SupportContactDataSource? supportContactApi;

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _tripsVisited = false;
  bool _settlementVisited = false;
  bool _accountVisited = false;
  bool _hasUrgentActivity = false;
  int _tripsRefreshRequest = 0;
  int _settlementRefreshRequest = 0;
  int _openCallsRefreshRequest = 0;
  int _settlementBadge = 0;
  bool _statusLoading = true;
  bool _suspended = false;
  int _restrictedIndex = 0;

  int? get _settlementIndex => widget.settlementApi == null ? null : 2;
  int? get _accountIndex {
    if (widget.accountApi == null) return null;
    return widget.settlementApi == null ? 2 : 3;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeAccess());
  }

  Future<void> _initializeAccess() async {
    try {
      final status = await widget.dispatchRepository.getStatus();
      if (!mounted) return;
      _suspended = status.status == 'SUSPENDED';
      if (_suspended) {
        widget.driverSocket?.disconnect();
        widget.fcmMessageService?.detachShellNavigator();
      } else {
        unawaited(_initializeFcm());
      }
    } catch (_) {
      // Individual screens retain their existing retry and unauthorized handling.
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
    unawaited(_refreshSettlementBadge());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.fcmMessageService?.detachShellNavigator();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_initializeAccess());
    }
  }

  Future<void> _initializeFcm() async {
    try {
      await widget.fcmTokenService?.registerIfNeeded();
      await widget.fcmMessageService?.attachShellNavigator((index) {
        if (!mounted) return;
        unawaited(_refreshSettlementBadge());
        unawaited(_selectTab(index, force: true));
      });
    } catch (_) {
      // FCM setup must not block the main driver workflow.
    }
  }

  Future<void> _refreshSettlementBadge() async {
    final api = widget.settlementApi;
    if (api == null) return;
    try {
      final items = await api.listSettlements();
      if (!mounted) return;
      setState(() {
        _settlementBadge = items.where((item) => item.countsForBadge).length;
      });
    } catch (_) {
      // Badge refresh failure must not block the main driver workflow.
    }
  }

  Future<void> _selectTab(int index, {bool force = false}) async {
    if (!force &&
        index != _selectedIndex &&
        _selectedIndex == 0 &&
        _hasUrgentActivity) {
      final leave = await showUrgentLeaveConfirmation(context);
      if (leave != true || !mounted) return;
      _hasUrgentActivity = false;
    }
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        _openCallsRefreshRequest++;
      }
      if (index == 1) {
        _tripsVisited = true;
        _tripsRefreshRequest++;
      }
      if (index == _settlementIndex) {
        _settlementVisited = true;
        _settlementRefreshRequest++;
      }
      if (index == _accountIndex) _accountVisited = true;
    });
    if (index == _settlementIndex) unawaited(_refreshSettlementBadge());
  }

  void _openSettlementTab() {
    final index = _settlementIndex;
    if (index != null) unawaited(_selectTab(index, force: true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_statusLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_suspended) {
      final pages = <Widget>[
        if (widget.settlementApi != null)
          SettlementListPage(
            api: widget.settlementApi!,
            onUnauthorized: widget.onUnauthorized,
            refreshRequest: _settlementRefreshRequest,
            onChanged: _refreshSettlementBadge,
          ),
        if (widget.accountApi != null)
          AccountPage(
            accountApi: widget.accountApi!,
            dispatchRepository: widget.dispatchRepository,
            localeController: widget.localeController,
            onUnauthorized: widget.onUnauthorized,
            onLogout: widget.onLogout,
            supportContactApi: widget.supportContactApi,
          ),
      ];
      final destinations = <NavigationDestination>[
        if (widget.settlementApi != null)
          NavigationDestination(
            icon: const Icon(Icons.payments_outlined),
            selectedIcon: const Icon(Icons.payments),
            label: l10n.tabSettlement,
          ),
        if (widget.accountApi != null)
          NavigationDestination(
            icon: const Icon(Icons.account_circle_outlined),
            selectedIcon: const Icon(Icons.account_circle),
            label: l10n.tabAccount,
          ),
      ];
      return Scaffold(
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.block,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.suspendedBanner,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: pages.isEmpty ? const SizedBox.shrink() : IndexedStack(
                index: _restrictedIndex.clamp(0, pages.length - 1),
                children: pages,
              ),
            ),
          ],
        ),
        bottomNavigationBar: destinations.length > 1
            ? NavigationBar(
                selectedIndex: _restrictedIndex,
                onDestinationSelected: (value) =>
                    setState(() => _restrictedIndex = value),
                destinations: destinations,
              )
            : null,
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          Offstage(
            offstage: _selectedIndex != 0,
            child: OpenCallsScreen(
              repository: widget.dispatchRepository,
              onUnauthorized: widget.onUnauthorized,
              onClaimed: () => _selectTab(1, force: true),
              onOpenSettlement: _openSettlementTab,
              driverSocket: widget.driverSocket,
              onUrgentActivityChanged: (active) {
                _hasUrgentActivity = active;
              },
              refreshRequest: _openCallsRefreshRequest,
            ),
          ),
          if (_tripsVisited)
            Offstage(
              offstage: _selectedIndex != 1,
              child: BookingListScreen(
                repository: widget.bookingRepository,
                onUnauthorized: widget.onUnauthorized,
                socketEvents: widget.driverSocket?.events,
                refreshRequest: _tripsRefreshRequest,
              ),
            ),
          if (_settlementVisited && widget.settlementApi != null)
            Offstage(
              offstage: _selectedIndex != _settlementIndex,
              child: SettlementListPage(
                api: widget.settlementApi!,
                onUnauthorized: widget.onUnauthorized,
                refreshRequest: _settlementRefreshRequest,
                onChanged: _refreshSettlementBadge,
              ),
            ),
          if (_accountVisited && widget.accountApi != null)
            Offstage(
              offstage: _selectedIndex != _accountIndex,
              child: AccountPage(
                accountApi: widget.accountApi!,
                dispatchRepository: widget.dispatchRepository,
                localeController: widget.localeController,
                onUnauthorized: widget.onUnauthorized,
                onLogout: widget.onLogout,
                supportContactApi: widget.supportContactApi,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => _selectTab(index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.campaign_outlined),
            selectedIcon: const Icon(Icons.campaign),
            label: l10n.tabNewCalls,
          ),
          NavigationDestination(
            icon: const Icon(Icons.route_outlined),
            selectedIcon: const Icon(Icons.route),
            label: l10n.tabMyTrips,
          ),
          if (widget.settlementApi != null)
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
              label: l10n.tabSettlement,
            ),
          if (widget.accountApi != null)
            NavigationDestination(
              icon: const Icon(Icons.account_circle_outlined),
              selectedIcon: const Icon(Icons.account_circle),
              label: l10n.tabAccount,
            ),
        ],
      ),
    );
  }
}
