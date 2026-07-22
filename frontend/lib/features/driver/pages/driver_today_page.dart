import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../services/driver_api_service.dart';
import '../services/driver_call_socket_service.dart';
import '../utils/driver_assignment_ended.dart';
import '../widgets/driver_today_trip_cards.dart';
import '../widgets/driver_workflow_widgets.dart';

class DriverTodayPage extends StatefulWidget {
  const DriverTodayPage({
    super.key,
    this.api,
    this.settlementApi,
    this.onSessionChanged,
    this.onNavigateToJobs,
    this.onNavigateToSettlement,
  });

  final DriverApiService? api;
  final DriverSettlementApiService? settlementApi;
  final VoidCallback? onSessionChanged;
  final VoidCallback? onNavigateToJobs;
  final VoidCallback? onNavigateToSettlement;

  @override
  State<DriverTodayPage> createState() => _DriverTodayPageState();
}

class _DriverTodayPageState extends State<DriverTodayPage> {
  late final DriverApiService _api;
  late final DriverSettlementApiService _settlementApi;
  Future<_TodayData>? _future;
  Future<DriverStatus>? _statusFuture;
  Future<String?>? _nameFuture;
  final Map<String, String?> _phoneCache = {};
  final Set<String> _phoneLoading = {};
  final Set<String> _notifiedOpenCalls = {};
  DriverCallSocketService? _callSocket;
  bool _completedExpanded = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _settlementApi = widget.settlementApi ?? const DriverSettlementApiService();
    _loadData();
    if (widget.api == null) {
      _connectCallSocket();
    }
  }

  @override
  void dispose() {
    _callSocket?.disconnect();
    super.dispose();
  }

  Future<void> _connectCallSocket() async {
    final token = await _api.getSavedToken();
    if (!mounted || token == null || token.isEmpty) return;
    final socket = DriverCallSocketService()
      ..onNewCall = (payload) {
        final bookingNumber = payload['bookingNumber']?.toString();
        final shouldAlert =
            bookingNumber == null || _notifiedOpenCalls.add(bookingNumber);
        if (shouldAlert) {
          SystemSound.play(SystemSoundType.alert);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_driverCallText(context, 'new_arrived'))),
          );
          _refresh();
        }
      }
      ..onClaimed = (_) {
        if (mounted) _refresh();
      }
      ..onConfirmed = (_) {
        if (mounted) _refresh();
      }
      ..onAssignmentReleased = (payload) {
        if (!mounted) return;
        final bookingNumber = payload['bookingNumber']?.toString();
        final reasonCode = payload['reasonCode']?.toString() ??
            payload['reason']?.toString();
        _refresh();
        if (bookingNumber == null || bookingNumber.isEmpty) return;
        final snackKey = DriverAssignmentEndedReason.snackbarKey(reasonCode);
        final text = context.l10n
            .t(snackKey)
            .replaceAll('{bookingNumber}', bookingNumber);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      }
      ..onReconnect = () {
        if (mounted) _refresh();
      };
    _callSocket = socket;
    await socket.connect(accessToken: token);
  }

  void _refresh() {
    _loadData(notifySession: true);
  }

  void _loadData({bool notifySession = false}) {
    setState(() {
      _future = _loadTodayData();
      _statusFuture = _api.getStatus();
      _nameFuture = _api.getDriverDisplayName();
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
    DriverOpenCalls openCalls;
    try {
      openCalls = await _api.getOpenCalls();
    } catch (_) {
      openCalls = const DriverOpenCalls(items: []);
    }
    final settlements = <String, Map<String, dynamic>>{};
    for (final booking in jobs.items) {
      if (booking.status != 'SETTLEMENT_PENDING') continue;
      try {
        final detail = await _settlementApi.getSettlement(
          booking.bookingNumber,
        );
        settlements[booking.bookingNumber] = detail;
      } catch (_) {
        // Unknown settlement state falls back to generic CTA and priority.
      }
    }
    return _TodayData(
      jobs: jobs,
      openCalls: openCalls.items,
      openCallBlockedReason: openCalls.blockedReason,
      openCallBlockedMessage: openCalls.message,
      settlements: settlements,
    );
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
              message: l10n.t('driver_load_failed'),
              onRetry: _refresh,
              retryLabel: l10n.t('driver_retry'),
            );
          }

          final data = snapshot.data;
          final items = data?.jobs.items ?? [];
          final openCalls = data?.openCalls ?? [];
          final settlements = data?.settlements ?? {};
          final current = DriverUx.selectCurrentTrip(
            items,
            settlementsByBooking: settlements,
          );
          final remaining =
              DriverUx.remainingTodayTrips(items, current: current)
                ..sort((a, b) {
                  final time = a.pickupTime.compareTo(b.pickupTime);
                  if (time != 0) return time;
                  return a.bookingNumber.compareTo(b.bookingNumber);
                });
          final completed = DriverUx.completedTodayTrips(items);
          final locationBooking = _locationBooking(items, current: current);

          if (current != null &&
              DriverUx.canContactCustomer(current.status) &&
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
                  onRefresh: _refresh,
                ),
                if (data?.openCallBlockedReason == 'UNPAID_SETTLEMENT') ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  DriverSettlementBlockBanner(
                    message: data?.openCallBlockedMessage ?? '',
                    onOpenSettlement: widget.onNavigateToSettlement ?? () {},
                  ),
                ],
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
                      hasActiveJob: locationBooking != null,
                      online: statusSnapshot.data?.online,
                      bookingNumber: locationBooking?.bookingNumber,
                      bookingStatus: locationBooking?.status,
                    );
                  },
                ),
                const SizedBox(height: AppTokens.spaceMd),
                if (openCalls.isNotEmpty &&
                    current == null &&
                    data?.openCallBlockedReason != 'UNPAID_SETTLEMENT') ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  _NewCallsPrompt(
                    count: openCalls.length,
                    onOpenJobs: widget.onNavigateToJobs,
                  ),
                ],
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
                      customerPhone: DriverUx.canContactCustomer(current.status)
                          ? _phoneCache[current.bookingNumber]
                          : null,
                      onOpenPrimary: () => _openPrimary(current),
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
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceSm,
                        ),
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

DriverBooking? _locationBooking(
  List<DriverBooking> items, {
  DriverBooking? current,
}) {
  const statuses = {
    'ON_ROUTE',
    'DRIVER_ARRIVED',
    'PICKED_UP',
    'DRIVER_ASSIGNED',
  };
  if (current != null && statuses.contains(current.status)) {
    return current;
  }
  for (final booking in items) {
    if (statuses.contains(booking.status)) return booking;
  }
  return null;
}

class _TodayData {
  const _TodayData({
    required this.jobs,
    required this.openCalls,
    this.openCallBlockedReason,
    this.openCallBlockedMessage,
    required this.settlements,
  });

  final DriverJobsToday jobs;
  final List<DriverOpenCall> openCalls;
  final String? openCallBlockedReason;
  final String? openCallBlockedMessage;
  final Map<String, Map<String, dynamic>> settlements;
}

String _driverCallText(BuildContext context, String key) {
  final language = Localizations.localeOf(context).languageCode;
  const values = {
    'en': {
      'new_arrived': 'A new booking has arrived',
      'waiting_title': 'Waiting calls',
      'claim': 'Claim call',
      'already_claimed': 'Another driver claimed it first.',
      'confirmed': 'Assignment confirmed.',
      'empty': 'No available calls.',
      'online_required': 'You can receive calls only when you are online.',
      'settlement_blocked':
          'You cannot receive new jobs yet. Please pay the commission and wait for admin review.',
    },
    'ko': {
      'new_arrived': '새 예약이 도착했습니다',
      'waiting_title': '대기 콜',
      'claim': '콜 잡기',
      'already_claimed': '다른 기사가 먼저 배정받았습니다',
      'confirmed': '배차가 확정되었습니다',
      'empty': '배차 가능한 콜이 없습니다',
      'online_required': '온라인 상태에서만 콜을 받을 수 있습니다',
      'settlement_blocked': '아직 신규 업무를 받을 수 없습니다. 커미션을 송금하고 관리자 확인을 기다려 주세요.',
    },
    'th': {
      'new_arrived': 'มีการจองใหม่เข้ามา',
      'waiting_title': 'งานที่รอรับ',
      'claim': 'รับงาน',
      'already_claimed': 'คนขับคนอื่นรับงานนี้ก่อนแล้ว',
      'confirmed': 'ยืนยันการรับงานแล้ว',
      'empty': 'ไม่มีงานที่พร้อมให้รับ',
      'online_required': 'รับงานได้เฉพาะเมื่อออนไลน์เท่านั้น',
      'settlement_blocked':
          'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
    },
  };
  return values[language]?[key] ?? values['en']![key] ?? key;
}

class _NewCallsPrompt extends StatelessWidget {
  const _NewCallsPrompt({required this.count, this.onOpenJobs});

  final int count;
  final VoidCallback? onOpenJobs;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.infoLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('driver_home_new_calls_title'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            l10n
                .t('driver_home_new_calls_message')
                .replaceAll('{count}', '$count'),
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onOpenJobs,
              icon: const Icon(Icons.work_outline),
              label: Text(l10n.t('driver_home_new_calls_cta')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.date,
    required this.tripCount,
    required this.nameFuture,
    required this.onRefresh,
  });

  final String date;
  final int tripCount;
  final Future<String?>? nameFuture;
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
          ],
        ),
      ],
    );
  }
}
