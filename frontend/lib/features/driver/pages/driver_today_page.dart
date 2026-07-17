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
import '../pages/driver_chat_page.dart';
import '../pages/driver_notifications_page.dart';
import '../services/driver_api_service.dart';
import '../services/driver_call_socket_service.dart';
import '../utils/driver_money_format.dart';
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
  final Set<String> _claimingCalls = {};
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
      settlements: settlements,
    );
  }

  Future<void> _claimOpenCall(DriverOpenCall call) async {
    if (_claimingCalls.contains(call.bookingNumber)) return;
    setState(() => _claimingCalls.add(call.bookingNumber));
    try {
      await _api.claimOpenCall(call.bookingNumber);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_driverCallText(context, 'confirmed'))),
      );
      _refresh();
    } catch (err) {
      if (!mounted) return;
      final isAlreadyClaimed =
          err is DriverApiException &&
          (err.statusCode == 409 || err.errorCode == 'ALREADY_ASSIGNED');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAlreadyClaimed
                ? _driverCallText(context, 'already_claimed')
                : userFacingError(
                    err,
                    fallback: context.l10n.t('driver_load_failed'),
                  ),
          ),
        ),
      );
      _refresh();
    } finally {
      if (mounted) {
        setState(() => _claimingCalls.remove(call.bookingNumber));
      }
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
      MaterialPageRoute(builder: (_) => DriverNotificationsPage(api: _api)),
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
          final hasActiveJob = items.any(
            (booking) => const {
              'DRIVER_ASSIGNED',
              'ON_ROUTE',
              'DRIVER_ARRIVED',
              'PICKED_UP',
              'SETTLEMENT_PENDING',
            }.contains(booking.status),
          );

          if (current != null &&
              DriverUx.canMessageCustomer(current.status) &&
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
                const SizedBox(height: AppTokens.spaceMd),
                FutureBuilder<DriverStatus>(
                  future: _statusFuture,
                  builder: (context, statusSnapshot) {
                    return _OpenCallsSection(
                      calls: openCalls,
                      online: statusSnapshot.data?.online ?? false,
                      hasActiveJob: hasActiveJob,
                      claimingCalls: _claimingCalls,
                      onClaim: _claimOpenCall,
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
                      customerPhone: DriverUx.canMessageCustomer(current.status)
                          ? _phoneCache[current.bookingNumber]
                          : null,
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

class _TodayData {
  const _TodayData({
    required this.jobs,
    required this.openCalls,
    required this.settlements,
  });

  final DriverJobsToday jobs;
  final List<DriverOpenCall> openCalls;
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
    },
    'ko': {
      'new_arrived': '새 예약이 도착했습니다',
      'waiting_title': '대기 콜',
      'claim': '콜 잡기',
      'already_claimed': '다른 기사가 먼저 배정받았습니다',
      'confirmed': '배차가 확정되었습니다',
      'empty': '배차 가능한 콜이 없습니다',
      'online_required': '온라인 상태에서만 콜을 받을 수 있습니다',
    },
    'th': {
      'new_arrived': 'มีการจองใหม่เข้ามา',
      'waiting_title': 'งานที่รอรับ',
      'claim': 'รับงาน',
      'already_claimed': 'คนขับคนอื่นรับงานนี้ก่อนแล้ว',
      'confirmed': 'ยืนยันการรับงานแล้ว',
      'empty': 'ไม่มีงานที่พร้อมให้รับ',
      'online_required': 'รับงานได้เฉพาะเมื่อออนไลน์เท่านั้น',
    },
  };
  return values[language]?[key] ?? values['en']![key] ?? key;
}

class _OpenCallsSection extends StatelessWidget {
  const _OpenCallsSection({
    required this.calls,
    required this.online,
    required this.hasActiveJob,
    required this.claimingCalls,
    required this.onClaim,
  });

  final List<DriverOpenCall> calls;
  final bool online;
  final bool hasActiveJob;
  final Set<String> claimingCalls;
  final ValueChanged<DriverOpenCall> onClaim;

  String _luggageSummary(DriverOpenCall call) {
    final luggage = call.luggage ?? {};
    final parts = <String>[];
    final c20 = luggage['carriers20Inch'] as num? ?? 0;
    final c24 = luggage['carriers24InchPlus'] as num? ?? 0;
    final golf = luggage['golfBags'] as num? ?? 0;
    final special = luggage['specialItems']?.toString().trim();
    if (c20 > 0) parts.add('20": ${c20.toInt()}');
    if (c24 > 0) parts.add('24"+: ${c24.toInt()}');
    if (golf > 0) parts.add('Golf: ${golf.toInt()}');
    if (special != null && special.isNotEmpty) parts.add(special);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final buttonEnabled = online && !hasActiveJob;
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined, color: AppTokens.primary),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  _driverCallText(context, 'waiting_title'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (!online)
            Text(
              _driverCallText(context, 'online_required'),
              style: const TextStyle(color: AppTokens.warning),
            )
          else if (calls.isEmpty)
            Text(
              _driverCallText(context, 'empty'),
              style: const TextStyle(color: AppTokens.textSecondary),
            )
          else
            ...calls.map((call) {
              final claiming = claimingCalls.contains(call.bookingNumber);
              final expectedIncome = call.driverExpectedIncomeAmount == null
                  ? null
                  : DriverMoneyFormat.money(
                      call.driverExpectedIncomeAmount!,
                      call.driverExpectedIncomeCurrency ?? call.currency,
                    );
              final customerTotal = call.customerPaymentAmount == null
                  ? null
                  : DriverMoneyFormat.money(
                      call.customerPaymentAmount!,
                      call.customerPaymentCurrency ?? call.currency,
                    );
              final luggage = _luggageSummary(call);
              return Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                child: Container(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    border: Border.all(
                      color: AppTokens.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${call.pickupDate} ${call.pickupTime}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text('${call.origin} → ${call.destination}'),
                      const SizedBox(height: 6),
                      Text(
                        '${call.serviceTypeName} · ${call.vehicleTypeName}',
                        style: const TextStyle(color: AppTokens.textSecondary),
                      ),
                      if (expectedIncome != null) ...[
                        const SizedBox(height: 8),
                        AppUi.summaryRow(
                          label: context.l10n.t('driver_expected_income'),
                          value: expectedIncome,
                          emphasize: true,
                        ),
                      ],
                      if (customerTotal != null) ...[
                        const SizedBox(height: 4),
                        AppUi.summaryRow(
                          label: context.l10n.t('driver_customer_total_amount'),
                          value: customerTotal,
                        ),
                      ],
                      if (luggage.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          luggage,
                          style: const TextStyle(color: AppTokens.textMuted),
                        ),
                      ],
                      const SizedBox(height: AppTokens.spaceMd),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: buttonEnabled && !claiming
                              ? () => onClaim(call)
                              : null,
                          icon: claiming
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.touch_app_outlined),
                          label: Text(_driverCallText(context, 'claim')),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
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
