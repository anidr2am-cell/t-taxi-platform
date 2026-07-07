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
  String? _processingBookingNumber;

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
        ),
      ),
    ).then((_) => _refresh());
  }

  Future<void> _runListAction(DriverBooking booking) async {
    if (_processingBookingNumber != null) return;
    setState(() => _processingBookingNumber = booking.bookingNumber);
    try {
      if (booking.allowedActions.contains('START_ON_ROUTE')) {
        await _api.startOnRoute(booking.bookingNumber);
      } else if (booking.allowedActions.contains('MARK_ARRIVED')) {
        await _api.markArrived(booking.bookingNumber);
      } else if (booking.allowedActions.contains('COMPLETE_TRIP')) {
        await _api.completeTrip(booking.bookingNumber);
      } else {
        _openDetail(booking);
        return;
      }
      if (!mounted) return;
      _loadData(notifySession: true);
    } on DriverApiException catch (err) {
      if (!mounted) return;
      if (driverIsAuthError(err)) {
        driverHandleApiError(context, err);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.message)));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(err, fallback: context.l10n.t('ui_action_failed')),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingBookingNumber = null);
      }
    }
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
              message: userFacingError(err, fallback: l10n.t('ui_load_failed')),
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
                      hasActiveJob: hasActiveJob,
                      online: statusSnapshot.data?.online,
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

  bool _isLocationTrackable(DriverBooking booking) {
    return const {
      'DRIVER_ASSIGNED',
      'DRIVER_ARRIVED',
      'PICKED_UP',
    }.contains(booking.status);
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
            onAction: () => _runListAction(b),
            processing: _processingBookingNumber == b.bookingNumber,
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
    required this.onAction,
    required this.processing,
  });

  final DriverBooking booking;
  final DriverJobGroup group;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final bool processing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actionKey = DriverUx.nextActionKey(booking);
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
                label: '${booking.passengerCount} ${l10n.t('passengers')}',
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
          if (actionKey != null && !isCompleted) ...[
            const SizedBox(height: AppTokens.spaceSm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: processing ? null : onAction,
                icon: processing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.touch_app, size: 18),
                label: Text(l10n.t(actionKey)),
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
