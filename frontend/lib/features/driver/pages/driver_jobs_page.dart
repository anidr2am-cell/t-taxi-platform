import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../driver_location/widgets/driver_live_location_control.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../services/driver_api_service.dart';
import 'driver_booking_detail_page.dart';

class DriverJobsPage extends StatefulWidget {
  const DriverJobsPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverJobsPage> createState() => _DriverJobsPageState();
}

class _DriverJobsPageState extends State<DriverJobsPage> {
  late final DriverApiService _api;
  Future<DriverJobsToday>? _future;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _api.getTodayBookings();
    });
  }

  void _openDetail(DriverBooking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverBookingDetailPage(
          bookingNumber: booking.bookingNumber,
          api: _api,
        ),
      ),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('driver_nav_jobs')),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('driver_refresh'),
          ),
        ],
      ),
      body: FutureBuilder<DriverJobsToday>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final err = snapshot.error!;
            if (driverIsAuthError(err)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) driverHandleApiError(context, err);
              });
            }
            return _StateMessage(
              title: l10n.t('driver_jobs_error_title'),
              message: err.toString(),
              action: ElevatedButton(
                onPressed: _refresh,
                child: Text(l10n.t('driver_retry')),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null || data.items.isEmpty) {
            return _StateMessage(
              title: l10n.t('driver_jobs_empty_title'),
              message: l10n.t('driver_jobs_empty_message'),
              action: ElevatedButton(
                onPressed: _refresh,
                child: Text(l10n.t('driver_refresh')),
              ),
            );
          }

          final grouped = DriverUx.groupBookings(data.items);
          final hasActiveJob = data.items.any(_isLocationTrackable);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  l10n.t('driver_jobs_today_date').replaceAll('{date}', data.date),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DriverLiveLocationControl(hasActiveJob: hasActiveJob),
                ..._buildGroup(
                  context,
                  l10n.t('driver_jobs_group_active'),
                  grouped[DriverJobGroup.active]!,
                ),
                ..._buildGroup(
                  context,
                  l10n.t('driver_jobs_group_upcoming'),
                  grouped[DriverJobGroup.upcoming]!,
                ),
                ..._buildGroup(
                  context,
                  l10n.t('driver_jobs_group_completed'),
                  grouped[DriverJobGroup.completed]!,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isLocationTrackable(DriverBooking booking) {
    return const {'DRIVER_ASSIGNED', 'DRIVER_ARRIVED', 'PICKED_UP'}.contains(booking.status);
  }

  List<Widget> _buildGroup(
    BuildContext context,
    String title,
    List<DriverBooking> items,
  ) {
    if (items.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ...items.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _JobCard(booking: b, onTap: () => _openDetail(b)),
      )),
    ];
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.booking, required this.onTap});

  final DriverBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actionKey = DriverUx.nextActionKey(booking);
    final statusKey = DriverUx.statusLabelKey(booking.status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      booking.bookingNumber,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _StatusChip(label: l10n.t(statusKey)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${booking.pickupDate} ${booking.pickupTime}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                booking.origin,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '→ ${booking.destination}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (booking.customerDisplayName != null)
                Text(booking.customerDisplayName!),
              Text(
                '${booking.passengerCount} ${l10n.t('passengers')} · ${booking.vehicleTypeName}',
              ),
              if (booking.flightNumber != null)
                Text('${l10n.t('flight_number')}: ${booking.flightNumber}'),
              if (actionKey != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.t(actionKey),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
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
