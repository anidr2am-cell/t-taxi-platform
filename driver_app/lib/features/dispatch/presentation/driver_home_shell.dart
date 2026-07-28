import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/firebase/fcm_token_service.dart';
import '../../../core/firebase/fcm_message_service.dart';
import '../../account/data/account_api.dart';
import '../../account/presentation/account_page.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/presentation/booking_list_screen.dart';
import '../../settlement/data/settlement_api.dart';
import '../../settlement/presentation/settlement_list_page.dart';
import '../data/dispatch_repository.dart';
import '../data/driver_socket_service.dart';
import 'open_calls_screen.dart';
import 'urgent_eta_dialog.dart';

class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({
    super.key,
    required this.bookingRepository,
    required this.dispatchRepository,
    required this.onUnauthorized,
    required this.onLogout,
    this.accountApi,
    this.settlementApi,
    this.driverSocket,
    this.fcmTokenService,
    this.fcmMessageService,
  });

  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;
  final DriverSocketConnection? driverSocket;
  final AccountDataSource? accountApi;
  final SettlementDataSource? settlementApi;
  final FcmTokenService? fcmTokenService;
  final FcmMessageService? fcmMessageService;

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _selectedIndex = 0;
  bool _tripsVisited = false;
  bool _settlementVisited = false;
  bool _accountVisited = false;
  bool _hasUrgentActivity = false;
  int _tripsRefreshRequest = 0;
  int _settlementRefreshRequest = 0;
  int _openCallsRefreshRequest = 0;
  int _settlementBadge = 0;

  int? get _settlementIndex => widget.settlementApi == null ? null : 2;
  int? get _accountIndex {
    if (widget.accountApi == null) return null;
    return widget.settlementApi == null ? 2 : 3;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSettlementBadge());
    unawaited(_initializeFcm());
  }

  @override
  void dispose() {
    widget.fcmMessageService?.detachShellNavigator();
    super.dispose();
  }

  Future<void> _initializeFcm() async {
    try {
      await widget.fcmTokenService?.registerIfNeeded();
      await widget.fcmMessageService?.attachShellNavigator((index) {
        if (!mounted) return;
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
                onUnauthorized: widget.onUnauthorized,
                onLogout: widget.onLogout,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => _selectTab(index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: '새 콜',
          ),
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: '내 운행',
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
              label: '정산',
            ),
          if (widget.accountApi != null)
            const NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle),
              label: '계정',
            ),
        ],
      ),
    );
  }
}
