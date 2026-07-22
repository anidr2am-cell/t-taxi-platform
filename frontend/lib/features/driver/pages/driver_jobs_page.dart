import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_location/widgets/driver_live_location_control.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../driver_auth.dart';
import '../driver_trip_contact.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';
import '../services/driver_api_service.dart';
import '../services/driver_call_socket_bridge.dart';
import '../services/driver_urgent_negotiation_controller.dart';
import '../utils/driver_money_format.dart';
import '../widgets/driver_trip_confirm_dialog.dart';
import '../widgets/driver_urgent_eta_dialog.dart';
import '../widgets/driver_urgent_negotiation_banner.dart';
import '../widgets/driver_workflow_widgets.dart';
import 'driver_booking_detail_page.dart';
import 'driver_trip_history_page.dart';

class DriverJobsPage extends StatefulWidget {
  const DriverJobsPage({super.key, this.api, this.onSessionChanged});

  final DriverApiService? api;
  final VoidCallback? onSessionChanged;

  @override
  State<DriverJobsPage> createState() => _DriverJobsPageState();
}

class _DriverJobsPageState extends State<DriverJobsPage>
    with SingleTickerProviderStateMixin {
  late final DriverApiService _api;
  late final TabController _tabController;
  Future<_JobsPageData>? _future;
  Future<DriverStatus>? _statusFuture;
  final Set<String> _claimingCalls = {};
  final Set<String> _lockingCalls = {};
  final Set<String> _hiddenUrgentCalls = {};
  final Map<String, _UrgentCallMeta> _urgentMeta = {};

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _tabController = TabController(length: 3, vsync: this);
    DriverCallSocketBridge.instance.onUrgentEvent = _handleUrgentSocketEvent;
    _loadData();
  }

  @override
  void dispose() {
    if (DriverCallSocketBridge.instance.onUrgentEvent ==
        _handleUrgentSocketEvent) {
      DriverCallSocketBridge.instance.onUrgentEvent = null;
    }
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    _loadData(notifySession: true);
  }

  void _loadData({bool notifySession = false}) {
    setState(() {
      _future = _loadPageData();
      _statusFuture = _api.getStatus();
    });
    if (notifySession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSessionChanged?.call();
      });
    }
  }

  Future<_JobsPageData> _loadPageData() async {
    final jobs = await _api.getTodayBookings();
    DriverOpenCalls openCalls;
    try {
      openCalls = await _api.getOpenCalls();
    } catch (_) {
      openCalls = const DriverOpenCalls(items: []);
    }
    return _JobsPageData(
      jobs: jobs,
      openCalls: _visibleOpenCalls(openCalls.items),
      openCallBlockedReason: openCalls.blockedReason,
      openCallBlockedMessage: openCalls.message,
    );
  }

  List<DriverOpenCall> _visibleOpenCalls(List<DriverOpenCall> calls) {
    return calls
        .map((call) {
          if (!call.isUrgentRequest) return call;
          final meta = _urgentMeta[call.bookingNumber];
          if (meta == null) return call;
          return call.copyWith(
            negotiationId: meta.negotiationId ?? call.negotiationId,
            minRequiredEtaMinutes:
                meta.minRequiredEtaMinutes ?? call.minRequiredEtaMinutes,
          );
        })
        .where(
          (call) =>
              !call.isUrgentRequest ||
              !_hiddenUrgentCalls.contains(call.bookingNumber),
        )
        .toList(growable: false);
  }

  void _handleUrgentSocketEvent(
    String event,
    Map<String, dynamic> payload,
  ) {
    final bookingNumber = payload['bookingNumber']?.toString();
    if (bookingNumber == null || bookingNumber.isEmpty) return;

    final minEta = (payload['minRequiredEtaMinutes'] as num?)?.toInt();
    final negotiationId = (payload['negotiationId'] as num?)?.toInt();
    final lockExpiresAt = payload['lockExpiresAt']?.toString();

    void mergeMeta() {
      final existing = _urgentMeta[bookingNumber];
      _urgentMeta[bookingNumber] = _UrgentCallMeta(
        negotiationId: negotiationId ?? existing?.negotiationId,
        minRequiredEtaMinutes: minEta ?? existing?.minRequiredEtaMinutes,
        lockExpiresAt: lockExpiresAt ?? existing?.lockExpiresAt,
      );
    }

    switch (event) {
      case 'new':
      case 'unlocked':
      case 'round-ended':
        setState(() {
          mergeMeta();
          if (event != 'new') {
            _hiddenUrgentCalls.remove(bookingNumber);
          }
        });
        _refresh();
        break;
      case 'locked':
      case 'cancelled':
        setState(() => _hiddenUrgentCalls.add(bookingNumber));
        _refresh();
        break;
      case 'confirmed':
        setState(() => _hiddenUrgentCalls.add(bookingNumber));
        _refresh();
        break;
      case 'eta-required':
        setState(mergeMeta);
        break;
    }
  }

  Future<void> _lockUrgentCall(DriverOpenCall call) async {
    if (_lockingCalls.contains(call.bookingNumber)) return;
    setState(() => _lockingCalls.add(call.bookingNumber));
    final l10n = context.l10n;
    try {
      final result = await _api.lockUrgentCall(call.bookingNumber);
      if (!mounted) return;
      final lockExpiresAt = result['lockExpiresAt']?.toString() ?? '';
      final dialogResult = await showDriverUrgentEtaDialog(
        context: context,
        api: _api,
        bookingNumber: call.bookingNumber,
        lockExpiresAt: lockExpiresAt,
        minRequiredEtaMinutes: call.minRequiredEtaMinutes,
      );
      if (!mounted) return;
      if (dialogResult?.submitted == true) {
        final decisionExpiresAt = dialogResult!.customerDecisionExpiresAt;
        if (decisionExpiresAt != null && decisionExpiresAt.isNotEmpty) {
          DriverUrgentNegotiationController.instance.startAwaitingCustomer(
            bookingNumber: call.bookingNumber,
            customerDecisionExpiresAt: decisionExpiresAt,
          );
        }
        setState(() => _hiddenUrgentCalls.add(call.bookingNumber));
      } else if (dialogResult?.timedOut == true) {
        DriverUrgentNegotiationController.instance.showMessagePhase(
          call.bookingNumber,
          DriverUrgentNegotiationBannerPhase.etaLockExpired,
        );
      }
      _refresh();
    } catch (err) {
      if (!mounted) return;
      final alreadyLocked =
          err is DriverApiException &&
          err.errorCode == 'URGENT_ALREADY_LOCKED';
      if (alreadyLocked) {
        setState(() => _hiddenUrgentCalls.add(call.bookingNumber));
      } else {
        _refresh();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyLocked
                ? l10n.t('driver_urgent_already_locked')
                : err is DriverApiException
                ? driverApiErrorMessage(
                    message: err.message,
                    errorCode: err.errorCode,
                    languageCode: Localizations.localeOf(context).languageCode,
                  )
                : userFacingError(err, fallback: l10n.t('driver_load_failed')),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _lockingCalls.remove(call.bookingNumber));
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

  void _openSettlementList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverSettlementListPage()),
    ).then((_) => _refresh());
  }

  void _openTripHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverTripHistoryPage(api: _api),
      ),
    );
  }

  Future<void> _confirmAndClaimOpenCall(DriverOpenCall call) async {
    final confirmed = await confirmDriverTripAction(
      context: context,
      titleKey: 'driver_claim_confirm_title',
      messageKey: 'driver_claim_confirm_message',
      confirmKey: 'driver_claim_call',
    );
    if (!confirmed || !mounted) return;
    await _claimOpenCall(call);
  }

  Future<void> _claimOpenCall(DriverOpenCall call) async {
    if (_claimingCalls.contains(call.bookingNumber)) return;
    setState(() => _claimingCalls.add(call.bookingNumber));
    final l10n = context.l10n;
    try {
      final booking = await _api.claimOpenCall(call.bookingNumber);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('driver_claim_success'))),
      );
      _openDetail(booking);
    } catch (err) {
      if (!mounted) return;
      final isAlreadyClaimed =
          err is DriverApiException &&
          (err.statusCode == 409 || err.errorCode == 'ALREADY_ASSIGNED');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAlreadyClaimed
                ? l10n.t('driver_claim_already_assigned')
                : err is DriverApiException
                ? driverApiErrorMessage(
                    message: err.message,
                    errorCode: err.errorCode,
                    languageCode: Localizations.localeOf(context).languageCode,
                  )
                : userFacingError(err, fallback: l10n.t('driver_load_failed')),
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DriverUrgentNegotiationBanner(),
        Expanded(
          child: FutureBuilder<_JobsPageData>(
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

              final data = snapshot.data!;
              final grouped = DriverUx.groupBookings(data.jobs.items);
              final locationBooking = _locationBooking(data.jobs.items);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: AppUi.pagePadding(context).copyWith(
                      top: AppTokens.spaceSm,
                      bottom: 0,
                    ),
                    child: FutureBuilder<DriverStatus>(
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
                  ),
                  TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(text: l10n.t('driver_jobs_tab_new')),
                      Tab(text: l10n.t('driver_jobs_tab_mine')),
                      Tab(text: l10n.t('driver_jobs_tab_past')),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _OpenCallsTab(
                          data: data,
                          statusFuture: _statusFuture,
                          claimingCalls: _claimingCalls,
                          lockingCalls: _lockingCalls,
                          onRefresh: _refresh,
                          onClaim: _confirmAndClaimOpenCall,
                          onLockUrgent: _lockUrgentCall,
                          onOpenSettlement: _openSettlementList,
                        ),
                        _MyJobsTab(
                          date: data.jobs.date,
                          active: grouped[DriverJobGroup.active]!,
                          upcoming: grouped[DriverJobGroup.upcoming]!,
                          onRefresh: _refresh,
                          onOpenDetail: _openDetail,
                        ),
                        _PastJobsTab(
                          completed: grouped[DriverJobGroup.completed]!,
                          onRefresh: _refresh,
                          onOpenDetail: _openDetail,
                          onOpenTripHistory: _openTripHistory,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
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
}

class _JobsPageData {
  const _JobsPageData({
    required this.jobs,
    required this.openCalls,
    this.openCallBlockedReason,
    this.openCallBlockedMessage,
  });

  final DriverJobsToday jobs;
  final List<DriverOpenCall> openCalls;
  final String? openCallBlockedReason;
  final String? openCallBlockedMessage;

  List<DriverOpenCall> get urgentCalls =>
      openCalls.where((call) => call.isUrgentRequest).toList(growable: false);

  List<DriverOpenCall> get regularCalls => openCalls
      .where((call) => !call.isUrgentRequest)
      .toList(growable: false);
}

class _UrgentCallMeta {
  const _UrgentCallMeta({
    this.negotiationId,
    this.minRequiredEtaMinutes,
    this.lockExpiresAt,
  });

  final int? negotiationId;
  final int? minRequiredEtaMinutes;
  final String? lockExpiresAt;
}

class _OpenCallsTab extends StatelessWidget {
  const _OpenCallsTab({
    required this.data,
    required this.statusFuture,
    required this.claimingCalls,
    required this.lockingCalls,
    required this.onRefresh,
    required this.onClaim,
    required this.onLockUrgent,
    required this.onOpenSettlement,
  });

  final _JobsPageData data;
  final Future<DriverStatus>? statusFuture;
  final Set<String> claimingCalls;
  final Set<String> lockingCalls;
  final VoidCallback onRefresh;
  final ValueChanged<DriverOpenCall> onClaim;
  final ValueChanged<DriverOpenCall> onLockUrgent;
  final VoidCallback onOpenSettlement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settlementBlocked =
        data.openCallBlockedReason == 'UNPAID_SETTLEMENT';

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: AppUi.pagePadding(context).copyWith(
          top: AppTokens.spaceMd,
          bottom: AppTokens.spaceLg,
        ),
        children: [
          if (settlementBlocked) ...[
            DriverSettlementBlockBanner(
              message: data.openCallBlockedMessage ?? '',
              onOpenSettlement: onOpenSettlement,
            ),
            const SizedBox(height: AppTokens.spaceMd),
          ],
          FutureBuilder<DriverStatus>(
            future: statusFuture,
            builder: (context, statusSnapshot) {
              final online = statusSnapshot.data?.online ?? false;
              final hasActiveJob = statusSnapshot.data?.hasActiveJob ?? false;
              final urgentCalls =
                  settlementBlocked ? const <DriverOpenCall>[] : data.urgentCalls;
              final regularCalls =
                  settlementBlocked ? const <DriverOpenCall>[] : data.regularCalls;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (urgentCalls.isNotEmpty) ...[
                    _UrgentCallsSection(
                      calls: urgentCalls,
                      online: online,
                      lockingCalls: lockingCalls,
                      onLock: onLockUrgent,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                  ],
                  _OpenCallsSection(
                    calls: regularCalls,
                    online: online,
                    hasActiveJob: hasActiveJob,
                    claimingCalls: claimingCalls,
                    onClaim: onClaim,
                    showOnlineRequired: !online,
                    showEmptyState:
                        online &&
                        urgentCalls.isEmpty &&
                        regularCalls.isEmpty,
                    emptyMessage: l10n.t('driver_open_calls_empty'),
                    onlineRequiredMessage:
                        l10n.t('driver_open_calls_online_required'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UrgentCallsSection extends StatelessWidget {
  const _UrgentCallsSection({
    required this.calls,
    required this.online,
    required this.lockingCalls,
    required this.onLock,
  });

  final List<DriverOpenCall> calls;
  final bool online;
  final Set<String> lockingCalls;
  final ValueChanged<DriverOpenCall> onLock;

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
    final l10n = context.l10n;
    final buttonEnabled = online;

    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.priority_high, color: AppTokens.warning),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  l10n.t('driver_urgent_section_title'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AppUi.statusBadge(
                l10n.t('driver_urgent_badge'),
                tone: AppStatusTone.warning,
              ),
            ],
          ),
          ...calls.map((call) {
            final locking = lockingCalls.contains(call.bookingNumber);
            final customerTotal = call.customerPaymentAmount != null
                ? DriverMoneyFormat.money(
                    call.customerPaymentAmount!,
                    call.customerPaymentCurrency ?? call.currency,
                  )
                : call.amount > 0
                ? DriverMoneyFormat.money(call.amount, call.currency)
                : null;
            final luggage = _luggageSummary(call);
            final minEta = call.minRequiredEtaMinutes;
            return Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSm),
              child: Container(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                decoration: BoxDecoration(
                  color: AppTokens.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  border: Border.all(
                    color: AppTokens.warning.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${call.pickupDate} ${call.pickupTime}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        AppUi.statusBadge(
                          l10n.t('driver_urgent_badge'),
                          tone: AppStatusTone.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DriverTripContact.displayLabelFor(DriverBookingLocation(address: call.origin))} → ${DriverTripContact.displayLabelFor(DriverBookingLocation(address: call.destination))}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${call.serviceTypeName} · ${call.vehicleTypeName} · '
                      '${call.passengerCount} ${l10n.t('driver_passengers')}',
                      style: const TextStyle(color: AppTokens.textSecondary),
                    ),
                    if (minEta != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n
                            .t('driver_urgent_min_eta_hint')
                            .replaceAll('{minutes}', '$minEta'),
                        style: const TextStyle(color: AppTokens.warning),
                      ),
                    ],
                    if (customerTotal != null) ...[
                      const SizedBox(height: 8),
                      AppUi.summaryRow(
                        label: l10n.t('driver_customer_total_amount'),
                        value: customerTotal,
                        emphasize: true,
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
                        onPressed: buttonEnabled && !locking
                            ? () => onLock(call)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.warning,
                        ),
                        icon: locking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(l10n.t('driver_urgent_accept')),
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

class _OpenCallsSection extends StatelessWidget {
  const _OpenCallsSection({
    required this.calls,
    required this.online,
    required this.hasActiveJob,
    required this.claimingCalls,
    required this.onClaim,
    required this.showOnlineRequired,
    required this.showEmptyState,
    required this.emptyMessage,
    required this.onlineRequiredMessage,
  });

  final List<DriverOpenCall> calls;
  final bool online;
  final bool hasActiveJob;
  final Set<String> claimingCalls;
  final ValueChanged<DriverOpenCall> onClaim;
  final bool showOnlineRequired;
  final bool showEmptyState;
  final String emptyMessage;
  final String onlineRequiredMessage;

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
    final l10n = context.l10n;
    final buttonEnabled = online;

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
                  l10n.t('driver_jobs_tab_new'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (showOnlineRequired)
            Text(
              onlineRequiredMessage,
              style: const TextStyle(color: AppTokens.warning),
            )
          else if (showEmptyState)
            Text(
              emptyMessage,
              style: const TextStyle(color: AppTokens.textSecondary),
            )
          else
            ...calls.map((call) {
              final claiming = claimingCalls.contains(call.bookingNumber);
              final customerTotal = call.customerPaymentAmount != null
                  ? DriverMoneyFormat.money(
                      call.customerPaymentAmount!,
                      call.customerPaymentCurrency ?? call.currency,
                    )
                  : call.amount > 0
                  ? DriverMoneyFormat.money(call.amount, call.currency)
                  : null;
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
                      Text(
                        '${DriverTripContact.displayLabelFor(DriverBookingLocation(address: call.origin))} → ${DriverTripContact.displayLabelFor(DriverBookingLocation(address: call.destination))}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${call.serviceTypeName} · ${call.vehicleTypeName} · '
                        '${call.passengerCount} ${l10n.t('driver_passengers')}',
                        style: const TextStyle(color: AppTokens.textSecondary),
                      ),
                      if (customerTotal != null) ...[
                        const SizedBox(height: 8),
                        AppUi.summaryRow(
                          label: l10n.t('driver_customer_total_amount'),
                          value: customerTotal,
                          emphasize: true,
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
                          label: Text(l10n.t('driver_claim_call')),
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

class _MyJobsTab extends StatelessWidget {
  const _MyJobsTab({
    required this.date,
    required this.active,
    required this.upcoming,
    required this.onRefresh,
    required this.onOpenDetail,
  });

  final String date;
  final List<DriverBooking> active;
  final List<DriverBooking> upcoming;
  final VoidCallback onRefresh;
  final ValueChanged<DriverBooking> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEmpty = active.isEmpty && upcoming.isEmpty;

    if (isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppUi.pagePadding(context),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.35,
              child: AppUi.emptyState(
                title: l10n.t('driver_jobs_empty_title'),
                message: l10n.t('driver_jobs_empty_message'),
                icon: Icons.work_off_outlined,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: AppUi.pagePadding(context).copyWith(
          top: AppTokens.spaceMd,
          bottom: AppTokens.spaceLg,
        ),
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n
                .t('driver_jobs_today_date')
                .replaceAll('{date}', date),
          ),
          ..._buildGroup(
            context,
            l10n.t('driver_jobs_group_active'),
            active,
            DriverJobGroup.active,
            onOpenDetail,
          ),
          ..._buildGroup(
            context,
            l10n.t('driver_jobs_group_upcoming'),
            upcoming,
            DriverJobGroup.upcoming,
            onOpenDetail,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(
    BuildContext context,
    String title,
    List<DriverBooking> items,
    DriverJobGroup group,
    ValueChanged<DriverBooking> onOpenDetail,
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
            onTap: () => onOpenDetail(b),
          ),
        ),
      ),
    ];
  }
}

class _PastJobsTab extends StatelessWidget {
  const _PastJobsTab({
    required this.completed,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onOpenTripHistory,
  });

  final List<DriverBooking> completed;
  final VoidCallback onRefresh;
  final ValueChanged<DriverBooking> onOpenDetail;
  final VoidCallback onOpenTripHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: AppUi.pagePadding(context).copyWith(
          top: AppTokens.spaceMd,
          bottom: AppTokens.spaceLg,
        ),
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenTripHistory,
              icon: const Icon(Icons.history, size: 18),
              label: Text(l10n.t('driver_nav_history')),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          if (completed.isEmpty)
            AppUi.emptyState(
              title: l10n.t('driver_jobs_group_completed'),
              message: l10n.t('driver_jobs_empty_message'),
              icon: Icons.check_circle_outline,
            )
          else ...[
            AppUi.sectionHeader(
              context,
              title: l10n.t('driver_jobs_group_completed'),
            ),
            ...completed.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                child: _JobCard(
                  booking: b,
                  group: DriverJobGroup.completed,
                  onTap: () => onOpenDetail(b),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
                  DriverTripContact.displayLabelFor(
                    booking.pickupLocation ??
                        DriverBookingLocation(address: booking.origin),
                  ),
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
                  DriverTripContact.displayLabelFor(
                    booking.destinationLocation ??
                        DriverBookingLocation(address: booking.destination),
                  ),
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
