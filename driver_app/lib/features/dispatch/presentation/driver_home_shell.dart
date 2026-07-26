import 'package:flutter/material.dart';

import '../../bookings/data/booking_repository.dart';
import '../../bookings/presentation/booking_list_screen.dart';
import '../data/dispatch_repository.dart';
import '../data/driver_socket_service.dart';
import 'open_calls_screen.dart';

class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({
    super.key,
    required this.bookingRepository,
    required this.dispatchRepository,
    required this.onUnauthorized,
    required this.onLogout,
    this.driverSocket,
  });

  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;
  final DriverSocketConnection? driverSocket;

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _selectedIndex = 0;
  bool _tripsVisited = false;

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 1) _tripsVisited = true;
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
              onClaimed: () => _selectTab(1),
              driverSocket: widget.driverSocket,
            ),
          ),
          if (_tripsVisited)
            Offstage(
              offstage: _selectedIndex != 1,
              child: BookingListScreen(
                repository: widget.bookingRepository,
                onUnauthorized: widget.onUnauthorized,
                onLogout: widget.onLogout,
                socketEvents: widget.driverSocket?.events,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: '새 콜',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: '내 운행',
          ),
        ],
      ),
    );
  }
}
