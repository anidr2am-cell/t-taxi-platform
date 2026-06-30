import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_location/widgets/driver_live_location_control.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';
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
  Future<DriverStatus>? _statusFuture;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _api.getTodayBookings();
      _statusFuture = _api.getStatus();
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
            return AppUi.loadingState();
          }
          if (snapshot.hasError) {
            final err = snapshot.error!;
            if (driverIsAuthError(err)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) driverHandleApiError(context, err);
              });
            }
            return AppUi.errorState(
              message: err.toString(),
              onRetry: _refresh,
              retryLabel: l10n.t('driver_retry'),
            );
          }
          final data = snapshot.data;
          if (data == null || data.items.isEmpty) {
            return AppUi.emptyState(
              title: l10n.t('driver_jobs_empty_title'),
              message: l10n.t('driver_jobs_empty_message'),
              icon: Icons.work_off_outlined,
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
                FutureBuilder<DriverStatus>(
                  future: _statusFuture,
                  builder: (context, statusSnapshot) {
                    if (statusSnapshot.hasError && driverIsAuthError(statusSnapshot.error!)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          driverHandleApiError(context, statusSnapshot.error!);
                        }
                      });
                    }
                    return DriverLiveLocationControl(
                      hasActiveJob: hasActiveJob,
                      online: statusSnapshot.data?.online,
                    );
                  },
                ),
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusLg,
        side: const BorderSide(color: AppTokens.border),
      ),
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
                  AppUi.statusBadge(
                    l10n.t(statusKey),
                    tone: AppUi.toneForBookingStatus(booking.status),
                  ),
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
                AppUi.actionBanner(message: l10n.t(actionKey)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
