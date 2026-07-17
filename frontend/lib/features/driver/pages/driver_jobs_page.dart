import 'package:flutter/material.dart';

import '../../../utils/user_facing_error.dart';
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
  const DriverJobsPage({super.key, this.api, this.onSessionChanged});

  final DriverApiService? api;
  final VoidCallback? onSessionChanged;

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
    _loadData();
  }

  void _refresh() {
    _loadData(notifySession: true);
  }

  void _loadData({bool notifySession = false}) {
    setState(() {
      _future = _api.getTodayBookings();
      _statusFuture = _api.getStatus();
    });
    if (notifySession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSessionChanged?.call();
      });
    }
  }

  void _openDetail(DriverBooking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverBookingDetailPage(
          bookingNumber: booking.bookingNumber,
          api: _api,
          showStatusControl: true,
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
              message: userFacingError(
                err,
                fallback: l10n.t('driver_load_failed'),
              ),
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
          final locationBooking = _locationBooking(data.items);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: AppUi.pagePadding(
                context,
              ).copyWith(bottom: AppTokens.spaceLg),
              children: [
                AppUi.sectionHeader(
                  context,
                  title: l10n
                      .t('driver_jobs_today_date')
                      .replaceAll('{date}', data.date),
                ),
                FutureBuilder<DriverStatus>(
                  future: _statusFuture,
                  builder: (context, statusSnapshot) {
                    if (statusSnapshot.hasError &&
                        driverIsAuthError(statusSnapshot.error!)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          driverHandleApiError(context, statusSnapshot.error!);
                        }
                      });
                    }
                    return DriverLiveLocationControl(
                      hasActiveJob: locationBooking != null,
                      online: statusSnapshot.data?.online,
                      bookingNumber: locationBooking?.bookingNumber,
                      bookingStatus: locationBooking?.status,
                    );
                  },
                ),
                ..._buildGroup(
                  context,
                  l10n.t('driver_jobs_group_active'),
                  grouped[DriverJobGroup.active]!,
                  DriverJobGroup.active,
                ),
                ..._buildGroup(
                  context,
                  l10n.t('driver_jobs_group_upcoming'),
                  grouped[DriverJobGroup.upcoming]!,
                  DriverJobGroup.upcoming,
                ),
                ..._buildGroup(
                  context,
                  l10n.t('driver_jobs_group_completed'),
                  grouped[DriverJobGroup.completed]!,
                  DriverJobGroup.completed,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  DriverBooking? _locationBooking(List<DriverBooking> items) {
    const statuses = {
      'ON_ROUTE',
      'DRIVER_ARRIVED',
      'PICKED_UP',
      'DRIVER_ASSIGNED',
    };
    for (final booking in items) {
      if (statuses.contains(booking.status)) return booking;
    }
    return null;
  }

  List<Widget> _buildGroup(
    BuildContext context,
    String title,
    List<DriverBooking> items,
    DriverJobGroup group,
  ) {
    if (items.isEmpty) return [];
    return [
      AppUi.sectionHeader(context, title: title),
      ...items.map(
        (b) => Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
          child: _JobCard(
            booking: b,
            group: group,
            onTap: () => _openDetail(b),
          ),
        ),
      ),
    ];
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.booking,
    required this.group,
    required this.onTap,
  });

  final DriverBooking booking;
  final DriverJobGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusKey = DriverUx.statusLabelKey(booking.status);
    final isActive = group == DriverJobGroup.active;
    final isCompleted = group == DriverJobGroup.completed;

    final card = AppUi.surfaceCard(
      onTap: onTap,
      backgroundColor: isActive ? AppTokens.primaryLight : AppTokens.surface,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isActive) ...[
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(right: AppTokens.spaceSm),
                  decoration: BoxDecoration(
                    color: AppTokens.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            booking.bookingNumber,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        AppUi.statusBadge(
                          l10n.t(statusKey),
                          tone: AppUi.toneForBookingStatus(booking.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 16,
                          color: AppTokens.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${booking.pickupDate} ${booking.pickupTime}',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.trip_origin, size: 16, color: AppTokens.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  booking.origin,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCompleted
                        ? AppTokens.textMuted
                        : AppTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: AppTokens.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  booking.destination,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCompleted
                        ? AppTokens.textMuted
                        : AppTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (booking.customerDisplayName != null)
                _MetaChip(
                  icon: Icons.person_outline,
                  label: booking.customerDisplayName!,
                  muted: isCompleted,
                ),
              _MetaChip(
                icon: Icons.people_outline,
                label:
                    '${booking.passengerCount} ${l10n.t('driver_passengers')}',
                muted: isCompleted,
              ),
              _MetaChip(
                icon: Icons.directions_car_outlined,
                label: booking.vehicleTypeName,
                muted: isCompleted,
              ),
              if (booking.flightNumber != null)
                _MetaChip(
                  icon: Icons.flight,
                  label: booking.flightNumber!,
                  muted: isCompleted,
                ),
            ],
          ),
          if (!isCompleted) ...[
            const SizedBox(height: AppTokens.spaceSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.t('driver_view_booking_detail')),
              ),
            ),
          ],
        ],
      ),
    );

    if (isCompleted) {
      return Opacity(opacity: 0.72, child: card);
    }
    return card;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: muted ? AppTokens.textMuted : AppTokens.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: muted ? AppTokens.textMuted : AppTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
