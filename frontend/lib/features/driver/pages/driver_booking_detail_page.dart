import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../pages/driver_chat_page.dart';
import '../services/driver_api_service.dart';
import '../services/driver_chat_api.dart';
import '../widgets/driver_qr_scan_sheet.dart';

class DriverBookingDetailPage extends StatefulWidget {
  const DriverBookingDetailPage({
    super.key,
    required this.bookingNumber,
    DriverApiService? api,
  }) : api = api ?? const DriverApiService();

  final String bookingNumber;
  final DriverApiService api;

  @override
  State<DriverBookingDetailPage> createState() =>
      _DriverBookingDetailPageState();
}

class _DriverBookingDetailPageState extends State<DriverBookingDetailPage> {
  late Future<DriverBooking> _future;
  Future<Map<String, dynamic>>? _settlementFuture;
  Future<int>? _chatUnreadFuture;
  bool _processing = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  void _loadBooking() {
    setState(() {
      _actionError = null;
      _future = widget.api.getBookingDetail(widget.bookingNumber);
      _settlementFuture = null;
      _chatUnreadFuture = const DriverChatApi().getRoom(widget.bookingNumber).then(
        (room) => (room['unreadCount'] as num?)?.toInt() ?? 0,
      ).catchError((_) => 0);
    });
  }

  void _loadSettlement() {
    setState(() {
      _settlementFuture = const DriverSettlementApiService()
          .getSettlement(widget.bookingNumber)
          .catchError((_) => <String, dynamic>{});
    });
  }

  Future<void> _runAction(
    Future<DriverBooking> Function() action,
    String messageKey,
  ) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _actionError = null;
    });
    final l10n = context.l10n;
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
        _processing = false;
      });
      if (updated.status == 'COMPLETED') {
        _loadSettlement();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t(messageKey))),
      );
    } on DriverApiException catch (err) {
      if (!mounted) return;
      setState(() => _processing = false);
      if (driverIsAuthError(err)) {
        driverHandleApiError(context, err);
        return;
      }
      if (err.isStaleStatus) {
        _loadBooking();
      }
      setState(() => _actionError = err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _actionError = err.toString();
      });
    }
  }

  Future<void> _openQrScan({required bool isBoarding}) async {
    if (_processing) return;
    final l10n = context.l10n;
    final result = await showDriverQrScanSheet(
      context: context,
      isBoarding: isBoarding,
      onSubmit: (token) async {
        if (isBoarding) {
          await widget.api.scanBoarding(widget.bookingNumber, token);
        } else {
          await widget.api.scanDropoff(widget.bookingNumber, token);
        }
      },
    );
    if (result == true && mounted) {
      _loadBooking();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBoarding ? l10n.t('driver_success_boarding') : l10n.t('driver_success_completed'),
          ),
        ),
      );
    }
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (!await launchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('driver_call_failed'))),
      );
    }
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverChatPage(bookingNumber: widget.bookingNumber),
      ),
    ).then((_) => _loadBooking());
  }

  void _openSettlementDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverSettlementDetailPage(
          bookingNumber: widget.bookingNumber,
          api: const DriverSettlementApiService(),
        ),
      ),
    ).then((_) {
      _loadBooking();
      _loadSettlement();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookingNumber),
        actions: [
          FutureBuilder<int>(
            future: _chatUnreadFuture,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return IconButton(
                tooltip: l10n.t('driver_open_chat'),
                onPressed: _openChat,
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              );
            },
          ),
          IconButton(
            onPressed: _loadBooking,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('driver_refresh'),
          ),
        ],
      ),
      body: FutureBuilder<DriverBooking>(
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
              message: '${l10n.t('driver_detail_error')}\n${err.toString()}',
              onRetry: _loadBooking,
              retryLabel: l10n.t('driver_retry'),
            );
          }
          final booking = snapshot.data!;
          if (booking.status == 'COMPLETED' && _settlementFuture == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadSettlement();
            });
          }

          final primaryKey = DriverUx.primaryActionKey(booking);
          final readOnly = DriverUx.isReadOnly(booking.status);

          return Column(
            children: [
              if (_processing)
                const LinearProgressIndicator(minHeight: 3),
              Expanded(
                child: ListView(
                  key: const Key('driverDetailScroll'),
                  padding: AppUi.pagePadding(context),
                  children: [
                    _StatusHeader(booking: booking),
                    if (_actionError != null) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.surfaceCard(
                        backgroundColor: AppTokens.errorLight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: AppTokens.error, size: 20),
                            const SizedBox(width: AppTokens.spaceSm),
                            Expanded(
                              child: Text(
                                _actionError!,
                                style: const TextStyle(color: AppTokens.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.adminDetailSection(
                      context: context,
                      title: l10n.t('driver_section_trip'),
                      child: Column(
                        children: [
                          AppUi.summaryRow(
                            label: l10n.t('driver_pickup_time'),
                            value: '${booking.pickupDate} ${booking.pickupTime}',
                            emphasize: true,
                          ),
                          AppUi.summaryRow(label: l10n.t('origin'), value: booking.origin),
                          AppUi.summaryRow(label: l10n.t('destination'), value: booking.destination),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.adminDetailSection(
                      context: context,
                      title: l10n.t('customer_info'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (booking.customerDisplayName != null)
                            AppUi.summaryRow(
                              label: l10n.t('name'),
                              value: booking.customerDisplayName!,
                            ),
                          if (DriverUx.canCallCustomer(
                            booking.status,
                            booking.customerPhone,
                          ))
                            AppUi.secondaryButton(
                              label: l10n.t('driver_call_customer'),
                              icon: Icons.phone,
                              onPressed: () => _callCustomer(booking.customerPhone!),
                              fullWidth: true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.adminDetailSection(
                      context: context,
                      title: l10n.t('passengers'),
                      child: Column(
                        children: [
                          AppUi.summaryRow(
                            label: l10n.t('passengers'),
                            value: booking.passengerCount.toString(),
                          ),
                          AppUi.summaryRow(label: l10n.t('vehicle'), value: booking.vehicleTypeName),
                          if (booking.luggage != null)
                            AppUi.summaryRow(
                              label: l10n.t('luggage'),
                              value: _formatLuggage(booking.luggage!),
                            ),
                        ],
                      ),
                    ),
                    if (booking.flightNumber != null) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      AppUi.adminDetailSection(
                        context: context,
                        title: l10n.t('flight_number'),
                        child: Column(
                          children: [
                            AppUi.summaryRow(
                              label: l10n.t('flight_number'),
                              value: booking.flightNumber!,
                            ),
                            if (booking.flightStatus != null)
                              AppUi.summaryRow(
                                label: l10n.t('status'),
                                value: booking.flightStatus!,
                              ),
                            if (booking.latestEstimatedArrival != null)
                              AppUi.summaryRow(
                                label: l10n.t('driver_estimated_arrival'),
                                value: booking.latestEstimatedArrival!,
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (booking.specialInstructions?.isNotEmpty == true) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      AppUi.adminDetailSection(
                        context: context,
                        title: l10n.t('special_requests'),
                        child: Text(
                          booking.specialInstructions!,
                          style: const TextStyle(color: AppTokens.textSecondary),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.adminDetailSection(
                      context: context,
                      title: l10n.t('driver_section_chat'),
                      child: AppUi.selectionTile(
                        title: l10n.t('driver_open_chat'),
                        icon: Icons.chat_bubble_outline,
                        onTap: _openChat,
                      ),
                    ),
                    if (booking.status == 'COMPLETED') ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      _SettlementSection(
                        future: _settlementFuture,
                        onOpenDetail: _openSettlementDetail,
                      ),
                    ],
                    if (readOnly)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                        child: Center(
                          child: AppUi.statusBadge(
                            l10n.t(DriverUx.statusLabelKey(booking.status)),
                            tone: AppUi.toneForBookingStatus(booking.status),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (primaryKey != null && !readOnly)
                AppUi.adminStickyActions(
                  actions: [
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _processing
                            ? null
                            : () => _onPrimaryAction(booking, primaryKey),
                        child: Text(l10n.t(primaryKey)),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  void _onPrimaryAction(DriverBooking booking, String actionKey) {
    if (booking.allowedActions.contains('MARK_ARRIVED')) {
      _runAction(
        () => widget.api.markArrived(widget.bookingNumber),
        'driver_success_arrived',
      );
      return;
    }
    if (booking.allowedActions.contains('SCAN_BOARDING_QR')) {
      _openQrScan(isBoarding: true);
      return;
    }
    if (booking.allowedActions.contains('SCAN_DROPOFF_QR')) {
      _openQrScan(isBoarding: false);
    }
  }

  String _formatLuggage(Map<String, dynamic> luggage) {
    return [
      '20": ${luggage['carriers20Inch'] ?? 0}',
      '24"+: ${luggage['carriers24InchPlus'] ?? 0}',
      'Golf: ${luggage['golfBags'] ?? 0}',
    ].join(' · ');
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.booking});

  final DriverBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusLabel = l10n.t(DriverUx.statusLabelKey(booking.status));
    final nextKey = DriverUx.nextActionKey(booking);

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTokens.primaryDark,
                  ),
                ),
              ),
              AppUi.statusBadge(
                statusLabel,
                tone: AppUi.toneForBookingStatus(booking.status),
              ),
            ],
          ),
          if (nextKey != null) ...[
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              l10n.t('driver_next_action'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            AppUi.actionBanner(
              message: l10n.t(nextKey),
              icon: Icons.flag,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettlementSection extends StatelessWidget {
  const _SettlementSection({
    required this.future,
    required this.onOpenDetail,
  });

  final Future<Map<String, dynamic>>? future;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('driver_section_settlement'),
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
              child: LinearProgressIndicator(),
            );
          }
          final detail = snapshot.data;
          if (detail == null || detail.isEmpty) {
            return Text(l10n.t('driver_settlement_loading_failed'));
          }
          final status = detail['commissionStatus'] as String? ?? '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${detail['commissionAmount']} ${detail['currency']}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ),
                  AppUi.statusBadge(
                    status,
                    tone: _settlementTone(status),
                  ),
                ],
              ),
              if (detail['rejectionReason'] != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                AppUi.summaryRow(
                  label: l10n.t('driver_rejection_reason'),
                  value: detail['rejectionReason'] as String,
                ),
              ],
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.secondaryButton(
                label: l10n.t('driver_view_settlement'),
                icon: Icons.receipt_long_outlined,
                onPressed: onOpenDetail,
                fullWidth: true,
              ),
            ],
          );
        },
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
}
