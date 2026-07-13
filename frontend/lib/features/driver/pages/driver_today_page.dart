import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_location/widgets/driver_live_location_control.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';
import '../pages/driver_booking_detail_page.dart';
import '../pages/driver_chat_page.dart';
import '../pages/driver_notifications_page.dart';
import '../services/driver_api_service.dart';
import '../widgets/driver_today_trip_cards.dart';

class DriverTodayPage extends StatefulWidget {
  const DriverTodayPage({
    super.key,
    this.api,
    this.settlementApi,
    this.onSessionChanged,
  });

  final DriverApiService? api;
  final DriverSettlementApiService? settlementApi;
  final VoidCallback? onSessionChanged;

  @override
  State<DriverTodayPage> createState() => _DriverTodayPageState();
}

class _DriverTodayPageState extends State<DriverTodayPage> {
  late final DriverApiService _api;
  late final DriverSettlementApiService _settlementApi;
  Future<_TodayData>? _future;
  Future<DriverStatus>? _statusFuture;
  Future<String?>? _nameFuture;
  Future<int>? _unreadFuture;
  final Map<String, String?> _phoneCache = {};
  final Set<String> _phoneLoading = {};
  bool _completedExpanded = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _settlementApi = widget.settlementApi ?? const DriverSettlementApiService();
    _loadData();
  }

  void _refresh() {
    _loadData(notifySession: true);
  }

  void _loadData({bool notifySession = false}) {
    setState(() {
      _future = _loadTodayData();
      _statusFuture = _api.getStatus();
      _nameFuture = _api.getDriverDisplayName();
      _unreadFuture = _api.getUnreadNotificationCount();
      _phoneCache.clear();
      _phoneLoading.clear();
    });
    if (notifySession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSessionChanged?.call();
      });
    }
  }

  Future<_TodayData> _loadTodayData() async {
    final jobs = await _api.getTodayBookings();
    final settlements = <String, Map<String, dynamic>>{};
    for (final booking in jobs.items) {
      if (booking.status != 'SETTLEMENT_PENDING') continue;
      try {
        final detail = await _settlementApi.getSettlement(booking.bookingNumber);
        settlements[booking.bookingNumber] = detail;
      } catch (_) {
        // Unknown settlement state falls back to generic CTA and priority.
      }
    }
    return _TodayData(jobs: jobs, settlements: settlements);
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

  void _openSettlement(DriverBooking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSettlementDetailPage(
          bookingNumber: booking.bookingNumber,
          api: _settlementApi,
        ),
      ),
    ).then((_) => _refresh());
  }

  void _openPrimary(DriverBooking booking) {
    if (booking.status == 'SETTLEMENT_PENDING') {
      _openSettlement(booking);
      return;
    }
    _openDetail(booking);
  }

  void _openChat(DriverBooking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverChatPage(
          bookingNumber: booking.bookingNumber,
          bookingDetailPageBuilder: (number) => DriverBookingDetailPage(
            bookingNumber: number,
            api: _api,
            showStatusControl: true,
          ),
        ),
      ),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverNotificationsPage(api: _api),
      ),
    ).then((_) => _refresh());
  }

  Future<void> _ensurePhone(DriverBooking booking) async {
    if (_phoneCache.containsKey(booking.bookingNumber) ||
        _phoneLoading.contains(booking.bookingNumber)) {
      return;
    }
    if (booking.customerPhone != null && booking.customerPhone!.isNotEmpty) {
      _phoneCache[booking.bookingNumber] = booking.customerPhone;
      return;
    }
    _phoneLoading.add(booking.bookingNumber);
    try {
      final detail = await _api.getBookingDetail(booking.bookingNumber);
      _phoneCache[booking.bookingNumber] = detail.customerPhone;
    } catch (_) {
      _phoneCache[booking.bookingNumber] = null;
    } finally {
      _phoneLoading.remove(booking.bookingNumber);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: FutureBuilder<_TodayData>(
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
          final items = data?.jobs.items ?? [];
          final settlements = data?.settlements ?? {};
          final current = DriverUx.selectCurrentTrip(
            items,
            settlementsByBooking: settlements,
          );
          final remaining = DriverUx.remainingTodayTrips(
            items,
            current: current,
          )..sort((a, b) {
            final time = a.pickupTime.compareTo(b.pickupTime);
            if (time != 0) return time;
            return a.bookingNumber.compareTo(b.bookingNumber);
          });
          final completed = DriverUx.completedTodayTrips(items);
          final hasActiveJob = items.any(
            (booking) => const {
              'DRIVER_ASSIGNED',
              'DRIVER_ARRIVED',
              'PICKED_UP',
            }.contains(booking.status),
          );

          if (current != null &&
              (current.customerPhone == null ||
                  current.customerPhone!.isEmpty) &&
              !_phoneCache.containsKey(current.bookingNumber) &&
              !_phoneLoading.contains(current.bookingNumber)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ensurePhone(current);
            });
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: AppUi.pagePadding(
                context,
              ).copyWith(bottom: AppTokens.spaceLg),
              children: [
                _TodayHeader(
                  date: data?.jobs.date ?? '',
                  tripCount: items
                      .where(
                        (b) =>
                            DriverUx.groupForStatus(b.status) !=
                            DriverJobGroup.completed,
                      )
                      .length,
                  nameFuture: _nameFuture,
                  unreadFuture: _unreadFuture,
                  onOpenNotifications: _openNotifications,
                  onRefresh: _refresh,
                ),
                const SizedBox(height: AppTokens.spaceMd),
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
                if (items.isEmpty) ...[
                  const SizedBox(height: AppTokens.spaceLg),
                  AppUi.emptyState(
                    title: l10n.t('driver_today_empty_title'),
                    message: l10n.t('driver_today_empty_message'),
                    icon: Icons.event_busy_outlined,
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Center(
                    child: TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.t('driver_refresh')),
                    ),
                  ),
                ] else ...[
                  if (current != null) ...[
                    DriverTodayCurrentTripCard(
                      booking: current,
                      settlement: settlements[current.bookingNumber],
                      customerPhone: _phoneCache[current.bookingNumber],
                      onOpenPrimary: () => _openPrimary(current),
                      onOpenChat: DriverUx.canMessageCustomer(current.status)
                          ? () => _openChat(current)
                          : null,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                  ],
                  if (remaining.isNotEmpty) ...[
                    AppUi.sectionHeader(
                      context,
                      title: l10n
                          .t('driver_today_remaining_title')
                          .replaceAll('{count}', '${remaining.length}'),
                    ),
                    ...remaining.map(
                      (booking) => Padding(
                        padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                        child: DriverTodayTripListTile(
                          booking: booking,
                          onTap: () => _openDetail(booking),
                        ),
                      ),
                    ),
                  ],
                  if (completed.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    AppUi.surfaceCard(
                      onTap: () => setState(
                        () => _completedExpanded = !_completedExpanded,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceMd,
                        vertical: AppTokens.spaceSm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n
                                  .t('driver_today_completed_title')
                                  .replaceAll('{count}', '${completed.length}'),
                              style: const TextStyle(
                                color: AppTokens.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            _completedExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: AppTokens.textMuted,
                          ),
                        ],
                      ),
                    ),
                    if (_completedExpanded)
                      ...completed.map(
                        (booking) => Padding(
                          padding: const EdgeInsets.only(
                            top: AppTokens.spaceSm,
                          ),
                          child: Opacity(
                            opacity: 0.72,
                            child: DriverTodayTripListTile(
                              booking: booking,
                              onTap: () => _openDetail(booking),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TodayData {
  const _TodayData({required this.jobs, required this.settlements});

  final DriverJobsToday jobs;
  final Map<String, Map<String, dynamic>> settlements;
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.date,
    required this.tripCount,
    required this.nameFuture,
    required this.unreadFuture,
    required this.onOpenNotifications,
    required this.onRefresh,
  });

  final String date;
  final int tripCount;
  final Future<String?>? nameFuture;
  final Future<int>? unreadFuture;
  final VoidCallback onOpenNotifications;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FutureBuilder<String?>(
                future: nameFuture,
                builder: (context, snapshot) {
                  final name = snapshot.data?.trim();
                  final greeting = name == null || name.isEmpty
                      ? l10n.t('driver_today_greeting_generic')
                      : l10n
                            .t('driver_today_greeting_named')
                            .replaceAll('{name}', name);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n
                            .t('driver_today_trip_count')
                            .replaceAll('{count}', '$tripCount'),
                        style: const TextStyle(color: AppTokens.textSecondary),
                      ),
                      if (date.isNotEmpty)
                        Text(
                          date,
                          style: const TextStyle(
                            color: AppTokens.textMuted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: l10n.t('driver_refresh'),
            ),
            FutureBuilder<int>(
              future: unreadFuture,
              builder: (context, snapshot) {
                final unread = snapshot.data ?? 0;
                return Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: IconButton(
                    onPressed: onOpenNotifications,
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: l10n.t('driver_nav_notifications'),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
