import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../pages/driver_booking_detail_page.dart';
import '../services/driver_api_service.dart';

enum _HistoryRange { last7Days, last30Days, all }

class DriverTripHistoryPage extends StatefulWidget {
  const DriverTripHistoryPage({
    super.key,
    this.api,
    this.settlementApi,
    this.showAppBar = true,
  });

  final DriverApiService? api;
  final DriverSettlementApiService? settlementApi;
  final bool showAppBar;

  @override
  State<DriverTripHistoryPage> createState() => _DriverTripHistoryPageState();
}

class _DriverTripHistoryPageState extends State<DriverTripHistoryPage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late final DriverSettlementApiService _settlementApi =
      widget.settlementApi ?? const DriverSettlementApiService();
  _HistoryRange _range = _HistoryRange.last7Days;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<dynamic> _pendingToday = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settlements = await _settlementApi.listSettlements();
      final today = await _api.getTodayBookings();
      final pending = today.items
          .where((booking) => booking.status == 'SETTLEMENT_PENDING')
          .map(
            (booking) => {
              'bookingNumber': booking.bookingNumber,
              'pickupDate': booking.pickupDate,
              'pickupTime': booking.pickupTime,
              'origin': booking.origin,
              'destination': booking.destination,
              'status': booking.status,
              'commissionStatus': 'PENDING',
            },
          )
          .toList();
      final mapped = settlements
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = mapped;
        _pendingToday = pending;
        _loading = false;
      });
    } catch (err) {
      if (driverIsAuthError(err) && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) driverHandleApiError(context, err);
        });
      }
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_load_failed'),
        );
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filteredItems() {
    final now = DateTime.now();
    DateTime? cutoff;
    switch (_range) {
      case _HistoryRange.last7Days:
        cutoff = now.subtract(const Duration(days: 7));
      case _HistoryRange.last30Days:
        cutoff = now.subtract(const Duration(days: 30));
      case _HistoryRange.all:
        cutoff = null;
    }
    return _items.where((item) {
      final completedAt = item['completedAt'] as String?;
      if (cutoff == null || completedAt == null || completedAt.isEmpty) {
        return true;
      }
      final parsed = DateTime.tryParse(completedAt.replaceFirst(' ', 'T'));
      if (parsed == null) return true;
      return !parsed.isBefore(cutoff);
    }).toList();
  }

  void _openDetail(String bookingNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _api,
          showStatusControl: true,
        ),
      ),
    );
  }

  void _openSettlement(String bookingNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSettlementDetailPage(
          bookingNumber: bookingNumber,
          api: _settlementApi,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = _filteredItems();
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(l10n.t('driver_nav_history')),
              actions: [
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            )
          : null,
      body: _loading
          ? AppUi.loadingState()
          : _error != null
          ? AppUi.errorState(
              message: _error!,
              onRetry: _load,
              retryLabel: l10n.t('driver_retry'),
            )
          : Column(
              children: [
                Padding(
                  padding: AppUi.pagePadding(context).copyWith(
                    top: AppTokens.spaceSm,
                    bottom: AppTokens.spaceSm,
                  ),
                  child: Text(
                    l10n.t('driver_history_subtitle'),
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                Padding(
                  padding: AppUi.pagePadding(context).copyWith(
                    top: 0,
                    bottom: AppTokens.spaceSm,
                  ),
                  child: SegmentedButton<_HistoryRange>(
                    segments: [
                      ButtonSegment(
                        value: _HistoryRange.last7Days,
                        label: Text(l10n.t('driver_history_range_7d')),
                      ),
                      ButtonSegment(
                        value: _HistoryRange.last30Days,
                        label: Text(l10n.t('driver_history_range_30d')),
                      ),
                      ButtonSegment(
                        value: _HistoryRange.all,
                        label: Text(l10n.t('driver_history_range_all')),
                      ),
                    ],
                    selected: {_range},
                    onSelectionChanged: (value) {
                      setState(() => _range = value.first);
                    },
                  ),
                ),
                if (_pendingToday.isNotEmpty)
                  Padding(
                    padding: AppUi.pagePadding(context).copyWith(bottom: 0),
                    child: AppUi.surfaceCard(
                      backgroundColor: AppTokens.warningLight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n
                                .t('driver_history_pending_settlement')
                                .replaceAll('{count}', '${_pendingToday.length}'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTokens.warning,
                            ),
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          ..._pendingToday.map((item) {
                            final bookingNumber =
                                item['bookingNumber'] as String? ?? '';
                            return TextButton(
                              onPressed: () => _openSettlement(bookingNumber),
                              child: Text(bookingNumber),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? AppUi.emptyState(
                          title: l10n.t('driver_history_empty'),
                          icon: Icons.history,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: AppUi.pagePadding(context),
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: AppTokens.spaceSm),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final bookingNumber =
                                  item['bookingNumber'] as String? ?? '';
                              final origin = item['origin'] as String? ?? '';
                              final destination =
                                  item['destination'] as String? ?? '';
                              final pickupDate =
                                  item['pickupDate'] as String? ?? '';
                              final pickupTime =
                                  item['pickupTime'] as String? ?? '';
                              final completedAt =
                                  item['completedAt'] as String? ?? '';
                              final commissionStatus =
                                  item['commissionStatus'] as String? ?? '';
                              final displayDate = completedAt.isNotEmpty
                                  ? completedAt
                                  : '$pickupDate $pickupTime'.trim();
                              return AppUi.surfaceCard(
                                onTap: () => _openDetail(bookingNumber),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayDate,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        AppUi.statusBadge(
                                          l10n.t('status_completed'),
                                          tone: AppStatusTone.success,
                                        ),
                                      ],
                                    ),
                                    if (origin.isNotEmpty ||
                                        destination.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        origin.isEmpty
                                            ? destination
                                            : '$origin → $destination',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            bookingNumber,
                                            style: const TextStyle(
                                              color: AppTokens.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        AppUi.statusBadge(
                                          _settlementLabel(
                                            l10n,
                                            commissionStatus,
                                          ),
                                          tone: _settlementTone(commissionStatus),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  AppStatusTone _settlementTone(String status) {
    switch (status) {
      case 'PAID':
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
      case 'OVERDUE':
        return AppStatusTone.error;
      case 'PENDING':
      case 'RECEIPT_SUBMITTED':
        return AppStatusTone.warning;
      default:
        return AppStatusTone.neutral;
    }
  }

  String _settlementLabel(AppLocalizations l10n, String status) {
    if (status.isEmpty) return l10n.t('driver_settlement_status');
    return status;
  }
}
