import 'package:flutter/material.dart';

import '../models/driver_booking.dart';
import '../services/driver_api_service.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import 'driver_booking_detail_page.dart';
import 'driver_notifications_page.dart';
import 'driver_login_page.dart';

class DriverJobsPage extends StatefulWidget {
  const DriverJobsPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverJobsPage> createState() => _DriverJobsPageState();
}

class _DriverJobsPageState extends State<DriverJobsPage> {
  late final DriverApiService _api;
  Future<DriverJobsToday>? _future;
  Future<Map<String, dynamic>>? _ratingFuture;
  Future<int>? _unreadFuture;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _api.getTodayBookings();
      _ratingFuture = _api.getRatingSummary();
      _unreadFuture = _api.getUnreadNotificationCount();
    });
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DriverNotificationsPage(api: _api)),
    ).then((_) => _refresh());
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverLoginPage()),
    );
  }

  void _openDetail(DriverBooking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverBookingDetailPage(bookingNumber: booking.bookingNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today’s Jobs'),
        actions: [
          FutureBuilder<int>(
            future: _unreadFuture,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return IconButton(
                onPressed: _openNotifications,
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverSettlementListPage()),
            ),
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Settlements',
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _ratingFuture,
            builder: (context, ratingSnapshot) {
              if (!ratingSnapshot.hasData) return const SizedBox.shrink();
              final rating = ratingSnapshot.data!;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: Text(
                      rating['averageRating'] == null
                          ? 'No ratings yet'
                          : '${rating['averageRating']} average',
                    ),
                    subtitle: Text('${rating['reviewCount'] ?? 0} reviews'),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: FutureBuilder<DriverJobsToday>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StateMessage(
              title: 'Could not load jobs',
              message: snapshot.error.toString(),
              action: ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
            );
          }
          final data = snapshot.data;
          if (data == null || data.items.isEmpty) {
            return _StateMessage(
              title: 'No jobs today',
              message: 'Assigned bookings for today will appear here.',
              action: ElevatedButton(onPressed: _refresh, child: const Text('Refresh')),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final booking = data.items[index];
                return _JobCard(
                  booking: booking,
                  onTap: () => _openDetail(booking),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemCount: data.items.length,
            ),
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.booking, required this.onTap});

  final DriverBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${booking.pickupTime} · ${booking.bookingNumber}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _StatusBadge(status: booking.status),
                ],
              ),
              const SizedBox(height: 8),
              Text('${booking.origin} → ${booking.destination}'),
              const SizedBox(height: 8),
              Text('${booking.passengerCount} passengers · ${booking.vehicleTypeName}'),
              if (booking.flightNumber != null) ...[
                const SizedBox(height: 4),
                Text('Flight ${booking.flightNumber}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(status.replaceAll('_', ' ')));
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.title,
    required this.message,
    required this.action,
  });

  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            action,
          ],
        ),
      ),
    );
  }
}
