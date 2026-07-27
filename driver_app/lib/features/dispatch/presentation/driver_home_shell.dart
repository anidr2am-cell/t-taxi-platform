import 'package:flutter/material.dart';

import '../../account/data/account_api.dart';
import '../../account/presentation/account_page.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/presentation/booking_list_screen.dart';
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
    this.driverSocket,
  });

  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;
  final DriverSocketConnection? driverSocket;
  final AccountDataSource? accountApi;

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _selectedIndex = 0;
  bool _tripsVisited = false;
  bool _accountVisited = false;
  bool _hasUrgentActivity = false;
  int _tripsRefreshRequest = 0;

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
      if (index == 1) {
        _tripsVisited = true;
        _tripsRefreshRequest++;
      }
      if (index == 2) _accountVisited = true;
    });
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
              driverSocket: widget.driverSocket,
              onUrgentActivityChanged: (active) {
                _hasUrgentActivity = active;
              },
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
          if (_accountVisited && widget.accountApi != null)
            Offstage(
              offstage: _selectedIndex != 2,
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
