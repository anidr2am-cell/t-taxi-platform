import 'package:flutter/material.dart';

import '../../bookings/data/booking_repository.dart';
import '../../bookings/presentation/booking_list_screen.dart';
import '../data/dispatch_repository.dart';
import 'open_calls_screen.dart';

class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({
    super.key,
    required this.bookingRepository,
    required this.dispatchRepository,
    required this.onUnauthorized,
    required this.onLogout,
  });

  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 0
          ? OpenCallsScreen(
              repository: widget.dispatchRepository,
              onUnauthorized: widget.onUnauthorized,
              onClaimed: () => setState(() => _selectedIndex = 1),
            )
          : BookingListScreen(
              repository: widget.bookingRepository,
              onUnauthorized: widget.onUnauthorized,
              onLogout: widget.onLogout,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
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
