import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/user_facing_error.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/config/map_provider_config.dart';
import '../../driver_location/services/driver_location_api_service.dart';
import '../../driver_location/widgets/driver_live_location_control.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';
import '../driver_auth.dart';
import '../driver_trip_contact.dart';
import '../driver_ux.dart';
import '../driver_trip_flow.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';
import '../services/driver_api_service.dart';
import '../utils/driver_money_format.dart';
import '../widgets/driver_status_control.dart';
import '../widgets/driver_trip_confirm_dialog.dart';
import 'driver_chat_page.dart';

class DriverBookingDetailPage extends StatefulWidget {
  const DriverBookingDetailPage({
    super.key,
    required this.bookingNumber,
    DriverApiService? api,
    this.chatPageBuilder,
    this.showStatusControl = false,
    this.locationApi,
    this.positionProvider,
    this.settlementApi,
  }) : api = api ?? const DriverApiService();

  final String bookingNumber;
  final DriverApiService api;
  final Widget Function(String bookingNumber)? chatPageBuilder;
  final bool showStatusControl;
  final DriverLocationApiService? locationApi;
  final DriverPositionProvider? positionProvider;
  final DriverSettlementApiService? settlementApi;

  @override
  State<DriverBookingDetailPage> createState() =>
      _DriverBookingDetailPageState();
}

class _DriverBookingDetailPageState extends State<DriverBookingDetailPage> {
  late Future<DriverBooking> _future;
  Future<DriverStatus>? _statusFuture;
  Future<Map<String, dynamic>>? _settlementFuture;
  bool _processing = false;
  bool _confirmingAction = false;
  String? _actionError;
  String? _processingKey;

  DriverSettlementApiService get _settlementApi =>
      widget.settlementApi ?? const DriverSettlementApiService();

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  void _loadBooking() {
    setState(() {
      _actionError = null;
      _future = widget.api.getBookingDetail(widget.bookingNumber);
      if (widget.showStatusControl) {
        _statusFuture = widget.api.getStatus();
      }
      _settlementFuture = null;
    });
  }

  void _reloadStatus() {
    if (!widget.showStatusControl || !mounted) return;
    setState(() {
      _statusFuture = widget.api.getStatus();
    });
  }

  void _loadSettlement() {
    setState(() {
      _settlementFuture = _settlementApi
          .getSettlement(widget.bookingNumber)
          .catchError((_) => <String, dynamic>{});
    });
  }

  Future<void> _showSettlementPrompt() async {
    Map<String, dynamic> detail = {};
    try {
      detail = await _settlementApi.getSettlement(widget.bookingNumber);
    } catch (_) {
      // The detail page can still retry with the authenticated driver endpoint.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SettlementPromptDialog(
        detail: detail,
        onOpenDetail: () {
          Navigator.of(dialogContext).pop();
          _openSettlementDetail();
        },
      ),
    );
  }

  Future<void> _runAction(
    Future<DriverBooking> Function() action,
    String messageKey, {
    bool endTripAction = false,
    String? processingKey,
  }) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _processingKey = processingKey;
      _actionError = null;
    });
    final l10n = context.l10n;
    try {
      final updated = await action();
      final refreshed = await widget.api
          .getBookingDetail(widget.bookingNumber)
          .catchError((_) => updated);
      if (!mounted) return;
      setState(() {
        _future = Future.value(refreshed);
        _processing = false;
        _processingKey = null;
      });
      if (refreshed.status == 'SETTLEMENT_PENDING' ||
          refreshed.status == 'COMPLETED') {
        _loadSettlement();
      }
      if (endTripAction && refreshed.status == 'SETTLEMENT_PENDING') {
        await _showSettlementPrompt();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t(messageKey))));
    } on DriverApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _processingKey = null;
      });
      if (driverIsAuthError(err)) {
        driverHandleApiError(context, err);
        return;
      }
      if (err.isStaleStatus) {
        _loadBooking();
      }
      setState(
        () => _actionError = driverApiErrorMessage(
          message: err.message,
          errorCode: err.errorCode,
          languageCode: l10n.languageCode,
          preferEndTripFailure: endTripAction,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _processingKey = null;
        _actionError = userFacingError(
          err,
          fallback: l10n.t('driver_action_failed'),
        );
      });
    }
  }

  Future<void> _releaseAssignment() async {
    if (_processing) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('driver_release_assignment_title')),
        content: Text(l10n.t('driver_release_assignment_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('driver_release_assignment_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('driver_release_assignment_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _processing) return;

    setState(() {
      _processing = true;
      _actionError = null;
    });

    try {
      await widget.api.releaseAssignment(widget.bookingNumber);
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('driver_release_assignment_success'))),
      );
      Navigator.of(context).pop(true);
    } on DriverApiException catch (err) {
      if (!mounted) return;
      setState(() => _processing = false);
      if (driverIsAuthError(err)) {
        driverHandleApiError(context, err);
        return;
      }
      if (err.isStaleStatus || err.statusCode == 409) {
        _loadBooking();
      }
      setState(
        () => _actionError = driverApiErrorMessage(
          message: err.message,
          errorCode: err.errorCode,
          languageCode: l10n.languageCode,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _actionError = userFacingError(
          err,
          fallback: l10n.t('driver_release_assignment_failed'),
        );
      });
    }
  }

  void _openCustomerChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            widget.chatPageBuilder?.call(widget.bookingNumber) ??
            DriverChatPage(
              bookingNumber: widget.bookingNumber,
              bookingDetailPageBuilder: (bookingNumber) =>
                  DriverBookingDetailPage(bookingNumber: bookingNumber),
            ),
      ),
    );
  }

  void _openSettlementDetail() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => DriverSettlementDetailPage(
              bookingNumber: widget.bookingNumber,
              api: _settlementApi,
            ),
          ),
        )
        .then((_) {
          _loadBooking();
          _loadSettlement();
        });
  }

  DriverBookingLocation _pickupLocation(DriverBooking booking) {
    return booking.pickupLocation ??
        DriverBookingLocation(
          address: booking.origin,
          latitude: booking.originLatitude,
          longitude: booking.originLongitude,
        );
  }

  DriverBookingLocation _destinationLocation(DriverBooking booking) {
    return booking.destinationLocation ??
        DriverBookingLocation(
          address: booking.destination,
          latitude: booking.destinationLatitude,
          longitude: booking.destinationLongitude,
        );
  }

  Future<void> _openMapsLocation(DriverBookingLocation location) async {
    final opened = await DriverTripContact.openMapsForLocation(location);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('driver_google_maps_failed'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookingNumber),
        actions: [
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
            final message = err is DriverApiException
                ? err.message
                : userFacingError(err, fallback: l10n.t('driver_detail_error'));
            return AppUi.errorState(
              message: message,
              onRetry: _loadBooking,
              retryLabel: l10n.t('driver_retry'),
            );
          }
          final booking = snapshot.data!;
          if ((booking.status == 'SETTLEMENT_PENDING' ||
                  booking.status == 'COMPLETED') &&
              _settlementFuture == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadSettlement();
            });
          }

          final primaryKey = DriverUx.primaryActionKey(booking);
          final actionToken = DriverTripFlow.primaryActionToken(booking);
          final readOnly = DriverUx.isReadOnly(booking.status);
          final showSettlementInfo = booking.status == 'SETTLEMENT_PENDING';
          final showCompletedInfo = booking.status == 'COMPLETED';
          final canReleaseAssignment = booking.status == 'DRIVER_ASSIGNED';

          return Column(
            children: [
              if (widget.showStatusControl)
                DriverStatusControl(
                  api: widget.api,
                  onStatusChanged: _reloadStatus,
                ),
              if (_processing) ...[
                const LinearProgressIndicator(minHeight: 3),
                if (_processingKey != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.spaceMd,
                      AppTokens.spaceXs,
                      AppTokens.spaceMd,
                      0,
                    ),
                    child: Text(
                      l10n.t(_processingKey!),
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              Expanded(
                child: ListView(
                  key: const Key('driverDetailScroll'),
                  padding: AppUi.pagePadding(context),
                  children: [
                    _StatusHeader(booking: booking),
                    if (widget.showStatusControl)
                      _DriverDetailLocationSection(
                        booking: booking,
                        statusFuture: _statusFuture,
                        api: widget.locationApi,
                        positionProvider: widget.positionProvider,
                        onRetryStatus: _reloadStatus,
                      ),
                    if (showSettlementInfo) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.surfaceCard(
                        backgroundColor: AppTokens.infoLight,
                        child: Text(
                          l10n.t('driver_trip_settlement_pending_info'),
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                    if (showCompletedInfo) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.surfaceCard(
                        backgroundColor: AppTokens.successLight,
                        child: Text(
                          l10n.t('driver_trip_completed_info'),
                          style: const TextStyle(
                            color: AppTokens.success,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                    if (_actionError != null) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.surfaceCard(
                        backgroundColor: AppTokens.errorLight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppTokens.error,
                              size: 20,
                            ),
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
                          if (booking.standbyConfirmed ||
                              booking.assignmentStatus == 'ACCEPTED' ||
                              booking.acceptedAt?.isNotEmpty == true) ...[
                            AppUi.summaryRow(
                              label: l10n.t('driver_standby_status'),
                              value:
                                  booking.standbyConfirmedAt ??
                                  booking.acceptedAt ??
                                  l10n.t('driver_standby_confirmed'),
                              emphasize: true,
                            ),
                          ] else if (booking.standbyAllowedAt?.isNotEmpty ==
                              true) ...[
                            AppUi.summaryRow(
                              label:
                                  booking.standbyReferenceTimeType ==
                                      'AIRPORT_ARRIVAL'
                                  ? l10n.t('driver_standby_airport_reference')
                                  : l10n.t(
                                      'driver_standby_departure_reference',
                                    ),
                              value:
                                  booking.standbyReferenceTime ??
                                  booking.scheduledPickupAt ??
                                  '${booking.pickupDate} ${booking.pickupTime}',
                            ),
                            AppUi.summaryRow(
                              label: l10n.t('driver_standby_available_from'),
                              value: booking.standbyAllowedAt!,
                            ),
                          ],
                          AppUi.summaryRow(
                            label: l10n.t('driver_pickup_time'),
                            value:
                                '${booking.pickupDate} ${booking.pickupTime}',
                            emphasize: true,
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          _DriverLocationCard(
                            key: const Key('driverPickupLocationCard'),
                            title: l10n.t('driver_detail_origin'),
                            location: _pickupLocation(booking),
                            onOpen: _openMapsLocation,
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          _DriverLocationCard(
                            key: const Key('driverDestinationLocationCard'),
                            title: l10n.t('driver_detail_destination'),
                            location: _destinationLocation(booking),
                            onOpen: _openMapsLocation,
                          ),
                          if (booking.customerPaymentAmount != null) ...[
                            const SizedBox(height: AppTokens.spaceXs),
                            AppUi.summaryRow(
                              label: l10n.t('driver_customer_total_amount'),
                              value: DriverMoneyFormat.money(
                                booking.customerPaymentAmount!,
                                booking.customerPaymentCurrency ??
                                    booking.currency,
                              ),
                              emphasize: true,
                            ),
                          ],
                          if (booking.nameSignRequested) ...[
                            const SizedBox(height: AppTokens.spaceSm),
                            AppUi.actionBanner(
                              message: l10n.t('driver_name_sign_required'),
                              icon: Icons.badge_outlined,
                            ),
                          ],
                          if (booking.hasAnyRouteCoordinate) ...[
                            const SizedBox(height: AppTokens.spaceMd),
                            _DriverRouteMap(booking: booking),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.adminDetailSection(
                      context: context,
                      title: l10n.t('driver_detail_customer_info'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (booking.customerDisplayName != null)
                            AppUi.summaryRow(
                              label: l10n.t('driver_detail_customer_name'),
                              value: booking.customerDisplayName!,
                            ),
                          if (DriverUx.canMessageCustomer(booking.status))
                            AppUi.secondaryButton(
                              label: l10n.t('driver_message_customer'),
                              icon: Icons.chat_bubble_outline,
                              onPressed: _openCustomerChat,
                              fullWidth: true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.adminDetailSection(
                      context: context,
                      title: l10n.t('driver_detail_passengers'),
                      child: Column(
                        children: [
                          AppUi.summaryRow(
                            label: l10n.t('driver_detail_passengers'),
                            value: booking.passengerCount.toString(),
                          ),
                          AppUi.summaryRow(
                            label: l10n.t('driver_detail_vehicle'),
                            value: booking.vehicleTypeName,
                          ),
                          if (booking.luggage != null)
                            AppUi.summaryRow(
                              label: l10n.t('driver_detail_luggage'),
                              value: _formatLuggage(booking.luggage!),
                            ),
                        ],
                      ),
                    ),
                    if (booking.flightNumber != null) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      AppUi.adminDetailSection(
                        context: context,
                        title: l10n.t('driver_detail_flight_number'),
                        child: Column(
                          children: [
                            AppUi.summaryRow(
                              label: l10n.t('driver_detail_flight_number'),
                              value: booking.flightNumber!,
                            ),
                            if (booking.flightStatus != null)
                              AppUi.summaryRow(
                                label: l10n.t('driver_detail_status'),
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
                        title: l10n.t('driver_detail_special_requests'),
                        child: Text(
                          booking.specialInstructions!,
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (booking.status == 'SETTLEMENT_PENDING' ||
                        booking.status == 'COMPLETED') ...[
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
                      child: FilledButton.icon(
                        onPressed: _processing
                            ? null
                            : () => _onPrimaryAction(
                                booking,
                                actionToken,
                                primaryKey,
                              ),
                        icon: const Icon(Icons.touch_app_outlined),
                        label: Text(l10n.t(primaryKey)),
                      ),
                    ),
                    if (canReleaseAssignment) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTokens.error,
                            side: const BorderSide(color: AppTokens.error),
                          ),
                          onPressed: _processing ? null : _releaseAssignment,
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(l10n.t('driver_release_assignment')),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onPrimaryAction(
    DriverBooking booking,
    String? actionToken,
    String actionLabelKey,
  ) async {
    if (_processing || _confirmingAction || actionToken == null) return;
    final titleKey = DriverTripFlow.confirmTitleKey(actionToken);
    final messageKey = DriverTripFlow.confirmMessageKey(actionToken);
    if (titleKey == null || messageKey == null) return;

    setState(() => _confirmingAction = true);
    final confirmed = await confirmDriverTripAction(
      context: context,
      titleKey: titleKey,
      messageKey: messageKey,
      confirmKey: DriverTripFlow.confirmButtonKey(actionToken),
      extraContent: actionToken == 'END_TRIP'
          ? _EndTripPaymentSummary(booking: booking)
          : null,
    );
    if (mounted) {
      setState(() => _confirmingAction = false);
    }
    if (!confirmed || !mounted) return;

    Future<DriverBooking> Function() action;
    switch (actionToken) {
      case 'START_ON_ROUTE':
        action = () => widget.api.startOnRoute(widget.bookingNumber);
        break;
      case 'ACCEPT_BOOKING':
        action = () => widget.api.confirmStandby(widget.bookingNumber);
        break;
      case 'MARK_ARRIVED':
        action = () => widget.api.markArrived(widget.bookingNumber);
        break;
      case 'MARK_PICKED_UP':
        action = () => widget.api.markPickedUp(widget.bookingNumber);
        break;
      case 'END_TRIP':
        action = () => widget.api.endTrip(widget.bookingNumber);
        break;
      default:
        return;
    }

    final successKey =
        DriverTripFlow.successMessageKey(actionToken) ?? actionLabelKey;
    await _runAction(
      action,
      successKey,
      endTripAction: actionToken == 'END_TRIP',
      processingKey: DriverTripFlow.processingMessageKey(actionToken),
    );
  }

  String _formatLuggage(Map<String, dynamic> luggage) {
    return [
      '20": ${luggage['carriers20Inch'] ?? 0}',
      '24"+: ${luggage['carriers24InchPlus'] ?? 0}',
      'Golf: ${luggage['golfBags'] ?? 0}',
    ].join(' · ');
  }
}

class _DriverDetailLocationSection extends StatelessWidget {
  const _DriverDetailLocationSection({
    required this.booking,
    required this.statusFuture,
    required this.onRetryStatus,
    this.api,
    this.positionProvider,
  });

  final DriverBooking booking;
  final Future<DriverStatus>? statusFuture;
  final DriverLocationApiService? api;
  final DriverPositionProvider? positionProvider;
  final VoidCallback onRetryStatus;

  static const _activeStatuses = {
    'DRIVER_ASSIGNED',
    'ON_ROUTE',
    'DRIVER_ARRIVED',
    'PICKED_UP',
  };

  @override
  Widget build(BuildContext context) {
    if (!_activeStatuses.contains(booking.status)) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<DriverStatus>(
      future: statusFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final err = snapshot.error!;
          if (driverIsAuthError(err)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) driverHandleApiError(context, err);
            });
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
            child: AppUi.surfaceCard(
              backgroundColor: AppTokens.warningLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sync_problem, color: AppTokens.warning),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          context.l10n.t('driver_location_status_load_failed'),
                          style: const TextStyle(
                            color: AppTokens.warning,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    context.l10n.t('driver_location_status_load_failed_detail'),
                    style: const TextStyle(color: AppTokens.textSecondary),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onRetryStatus,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.t('driver_location_retry')),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return DriverLiveLocationControl(
          hasActiveJob: true,
          online: snapshot.data?.online,
          bookingNumber: booking.bookingNumber,
          bookingStatus: booking.status,
          api: api,
          positionProvider: positionProvider,
        );
      },
    );
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
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppTokens.textSecondary),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            AppUi.actionBanner(message: l10n.t(nextKey), icon: Icons.flag),
          ],
        ],
      ),
    );
  }
}

class _EndTripPaymentSummary extends StatelessWidget {
  const _EndTripPaymentSummary({required this.booking});

  final DriverBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <Widget>[];
    final amount = booking.customerPaymentAmount;
    final currency = booking.currency?.trim();
    if (amount != null &&
        amount > 0 &&
        currency != null &&
        currency.isNotEmpty) {
      rows.add(
        AppUi.summaryRow(
          label: l10n.t('driver_customer_payment_amount'),
          value: DriverMoneyFormat.money(amount, currency),
          emphasize: true,
        ),
      );
    }
    final paymentLabel = _paymentMethodLabel(
      l10n,
      booking.customerPaymentMethod ?? booking.paymentMethodLabel,
    );
    if (paymentLabel != null) {
      rows.add(
        AppUi.summaryRow(
          label: l10n.t('driver_payment_method'),
          value: paymentLabel,
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.warningLight,
      padding: const EdgeInsets.all(AppTokens.spaceSm),
      child: Column(children: rows),
    );
  }

  String? _paymentMethodLabel(AppLocalizations l10n, String? value) {
    switch (value) {
      case 'PAY_DRIVER':
      case 'PAY_DRIVER_AT_DESTINATION':
        return l10n.t('driver_payment_method_pay_driver');
      case 'BANK_TRANSFER':
        return l10n.t('driver_payment_method_bank_transfer');
      case 'CARD':
      case 'CREDIT_CARD':
        return l10n.t('driver_payment_method_card');
      case null:
      case '':
        return null;
      default:
        return null;
    }
  }
}

class _DriverLocationCard extends StatelessWidget {
  const _DriverLocationCard({
    super.key,
    required this.title,
    required this.location,
    required this.onOpen,
  });

  final String title;
  final DriverBookingLocation location;
  final Future<void> Function(DriverBookingLocation location) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final displayName = location.displayName.isNotEmpty
        ? location.displayName
        : l10n.t('driver_location_unavailable');
    final address = location.secondaryAddress;
    final canOpen =
        DriverTripContact.googleMapsUriForLocation(location) != null;

    final content = AppUi.surfaceCard(
      backgroundColor: AppTokens.surfaceMuted,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            title == l10n.t('driver_detail_origin')
                ? Icons.trip_origin
                : Icons.location_on_outlined,
            color: AppTokens.primary,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                if (address != null) ...[
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(
                    address,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                if (canOpen) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 18,
                        color: AppTokens.primary,
                      ),
                      const SizedBox(width: AppTokens.spaceXs),
                      Flexible(
                        child: Text(
                          l10n.t('driver_open_google_maps'),
                          style: const TextStyle(
                            color: AppTokens.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (canOpen)
            const Padding(
              padding: EdgeInsets.only(left: AppTokens.spaceXs),
              child: Icon(Icons.open_in_new, color: AppTokens.primary),
            ),
        ],
      ),
    );

    if (!canOpen) return content;
    return Semantics(
      button: true,
      label: '${l10n.t('driver_open_google_maps')}: $displayName',
      child: InkWell(
        borderRadius: AppTokens.borderRadiusSm,
        onTap: () => onOpen(location),
        child: content,
      ),
    );
  }
}

class _DriverRouteMap extends StatelessWidget {
  const _DriverRouteMap({required this.booking});

  final DriverBooking booking;

  @override
  Widget build(BuildContext context) {
    final origin =
        booking.originLatitude != null && booking.originLongitude != null
        ? LatLng(booking.originLatitude!, booking.originLongitude!)
        : null;
    final destination =
        booking.destinationLatitude != null &&
            booking.destinationLongitude != null
        ? LatLng(booking.destinationLatitude!, booking.destinationLongitude!)
        : null;
    final points = [origin, destination].nonNulls.toList();
    if (points.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: AppTokens.borderRadiusSm,
      child: SizedBox(
        key: const Key('driverRouteMap'),
        height: 220,
        child: FlutterMap(
          options: points.length == 1
              ? MapOptions(initialCenter: points.first, initialZoom: 15)
              : MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(36),
                    maxZoom: 15,
                  ),
                ),
          children: [
            TileLayer(
              urlTemplate: MapProviderConfig.tileUrlTemplate,
              userAgentPackageName: 'dev.ttaxi.frontend',
            ),
            MarkerLayer(
              markers: [
                if (origin != null)
                  Marker(
                    point: origin,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.trip_origin,
                      color: AppTokens.primary,
                      size: 32,
                    ),
                  ),
                if (destination != null)
                  Marker(
                    point: destination,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      color: AppTokens.error,
                      size: 36,
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementPromptDialog extends StatelessWidget {
  const _SettlementPromptDialog({
    required this.detail,
    required this.onOpenDetail,
  });

  final Map<String, dynamic> detail;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final payment = detail['paymentInstructions'] is Map
        ? Map<String, dynamic>.from(detail['paymentInstructions'] as Map)
        : <String, dynamic>{};
    final commissionAmount =
        (detail['companyCommissionAmount'] as num?) ??
        (detail['commissionAmount'] as num?);
    final currency =
        detail['companyCommissionCurrency'] as String? ??
        detail['currency'] as String?;
    final promptPayQrImageUrl = payment['promptPayQrImageUrl'] as String?;
    return AlertDialog(
      title: Text(l10n.t('driver_settlement_popup_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.t('driver_settlement_popup_message')),
            if (commissionAmount != null) ...[
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.summaryRow(
                label: l10n.t('driver_company_commission'),
                value: DriverMoneyFormat.money(commissionAmount, currency),
                emphasize: true,
              ),
            ],
            if (payment.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSm),
              if ((payment['bankName'] as String? ?? '').isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('admin_settings_bank_name'),
                  value: payment['bankName'] as String,
                ),
              if ((payment['accountName'] as String? ?? '').isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('admin_settings_account_name'),
                  value: payment['accountName'] as String,
                ),
              if ((payment['accountNumber'] as String? ?? '').isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('admin_settings_account_number'),
                  value: payment['accountNumber'] as String,
                ),
              if ((payment['promptPayNumber'] as String? ?? '').isNotEmpty)
                AppUi.summaryRow(
                  label: 'PromptPay',
                  value: payment['promptPayNumber'] as String,
                ),
              if (promptPayQrImageUrl != null &&
                  promptPayQrImageUrl.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Image.network(
                  const PlatformSettingsApiService()
                      .assetUri(promptPayQrImageUrl)
                      .toString(),
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ],
            ],
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              l10n.t('driver_settlement_next_job_notice'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('support_close_button')),
        ),
        FilledButton.icon(
          onPressed: onOpenDetail,
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(l10n.t('driver_settlement_upload')),
        ),
      ],
    );
  }
}

class _SettlementSection extends StatelessWidget {
  const _SettlementSection({required this.future, required this.onOpenDetail});

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
                  Text(l10n.t('driver_settlement_status')),
                  const Spacer(),
                  AppUi.statusBadge(status, tone: _settlementTone(status)),
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
