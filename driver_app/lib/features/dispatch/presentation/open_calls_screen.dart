import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/airport_label_resolver.dart';
import '../../bookings/data/booking_models.dart';
import '../../bookings/presentation/booking_display_formatters.dart';
import '../../bookings/presentation/booking_meeting_gate.dart';
import '../data/dispatch_models.dart';
import '../data/dispatch_repository.dart';
import '../data/driver_socket_service.dart';
import 'urgent_awaiting_banner.dart';
import 'urgent_eta_dialog.dart';
import 'vehicle_select_sheet.dart';

class OpenCallsScreen extends StatefulWidget {
  const OpenCallsScreen({
    super.key,
    required this.repository,
    required this.onUnauthorized,
    required this.onClaimed,
    this.onOpenSettlement,
    this.driverSocket,
    this.onUrgentActivityChanged,
    this.refreshRequest = 0,
  });

  final DispatchReader repository;
  final Future<void> Function() onUnauthorized;
  final VoidCallback onClaimed;
  final VoidCallback? onOpenSettlement;
  final DriverSocketConnection? driverSocket;
  final ValueChanged<bool>? onUrgentActivityChanged;
  final int refreshRequest;

  @override
  State<OpenCallsScreen> createState() => _OpenCallsScreenState();
}

class _OpenCallsScreenState extends State<OpenCallsScreen>
    with WidgetsBindingObserver {
  DriverDispatchStatus? _status;
  OpenCallList? _calls;
  ApiException? _statusError;
  ApiException? _callsError;
  bool _loadingStatus = true;
  bool _loadingCalls = false;
  bool _changingOnline = false;
  final Set<String> _claiming = {};
  final Set<String> _lockingUrgent = {};
  final Set<String> _hiddenUrgent = {};
  StreamSubscription<DriverSocketEvent>? _socketSubscription;
  bool _foreground = true;
  bool _showNewCallNotice = false;
  String? _activeUrgentBooking;
  String? _customerDecisionExpiresAt;
  UrgentAwaitingPhase? _awaitingPhase;

  bool get _hasUrgentActivity => _activeUrgentBooking != null;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _socketSubscription = widget.driverSocket?.events.listen(
      _handleSocketEvent,
    );
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketSubscription?.cancel();
    widget.driverSocket?.disconnect();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OpenCallsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRequest != widget.refreshRequest) {
      unawaited(_loadStatus());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground && _status?.online == true) {
      unawaited(_connectSocket());
    } else {
      widget.driverSocket?.disconnect();
    }
  }

  Future<void> _connectSocket() async {
    try {
      await widget.driverSocket?.connect();
    } catch (_) {
      // REST remains the source of truth if the foreground socket is unavailable.
    }
  }

  void _syncSocket(DriverDispatchStatus status) {
    if (status.online && _foreground) {
      unawaited(_connectSocket());
    } else {
      widget.driverSocket?.disconnect();
    }
  }

  void _handleSocketEvent(DriverSocketEvent event) {
    if (!mounted || _status?.online != true || !_foreground) return;
    switch (event.type) {
      case DriverSocketEventType.newCall:
        setState(() => _showNewCallNotice = true);
        unawaited(_loadCalls());
      case DriverSocketEventType.callClaimed:
      case DriverSocketEventType.callConfirmed:
      case DriverSocketEventType.assignmentReleased:
      case DriverSocketEventType.reconnected:
        unawaited(_loadCalls());
      case DriverSocketEventType.urgentCallNew:
        final bookingNumber = _bookingNumber(event.payload);
        setState(() {
          if (bookingNumber != null) _hiddenUrgent.remove(bookingNumber);
          _showNewCallNotice = true;
        });
        unawaited(_loadCalls());
      case DriverSocketEventType.urgentCallLocked:
        final bookingNumber = _bookingNumber(event.payload);
        final lockedDriverId = _intValue(event.payload['lockedDriverId']);
        final isMine =
            bookingNumber == _activeUrgentBooking ||
            (lockedDriverId != null && lockedDriverId == _status?.driverId);
        if (!isMine && bookingNumber != null) {
          setState(() => _hiddenUrgent.add(bookingNumber));
        }
        unawaited(_loadCalls());
      case DriverSocketEventType.urgentCallEtaRequired:
        final bookingNumber = _bookingNumber(event.payload);
        if (bookingNumber != null && _activeUrgentBooking == null) {
          _setUrgentActivity(bookingNumber);
        }
      case DriverSocketEventType.urgentCallRoundEnded:
        final bookingNumber = _bookingNumber(event.payload);
        if (bookingNumber != null) {
          setState(() => _hiddenUrgent.remove(bookingNumber));
        }
        if (bookingNumber == _activeUrgentBooking) {
          _clearUrgentActivity();
          _showMessage(
            AppLocalizations.of(context).customerRejectedOrRoundEnded,
          );
        }
        unawaited(_loadCalls());
      case DriverSocketEventType.urgentCallConfirmed:
        final bookingNumber = _bookingNumber(event.payload);
        if (bookingNumber == _activeUrgentBooking) {
          setState(() => _awaitingPhase = UrgentAwaitingPhase.confirmed);
          Future<void>.delayed(const Duration(milliseconds: 800), () {
            if (!mounted || bookingNumber != _activeUrgentBooking) return;
            _clearUrgentActivity();
            widget.onClaimed();
          });
        }
        unawaited(_loadCalls());
      case DriverSocketEventType.urgentCallCancelled:
        final bookingNumber = _bookingNumber(event.payload);
        if (bookingNumber != null) {
          setState(() => _hiddenUrgent.add(bookingNumber));
        }
        if (bookingNumber == _activeUrgentBooking) {
          _clearUrgentActivity();
          _showMessage(AppLocalizations.of(context).negotiationCancelled);
        }
        unawaited(_loadCalls());
      case DriverSocketEventType.urgentCallUnlocked:
        final bookingNumber = _bookingNumber(event.payload);
        if (bookingNumber != null) {
          setState(() => _hiddenUrgent.remove(bookingNumber));
        }
        unawaited(_loadCalls());
    }
  }

  String? _bookingNumber(Map<String, dynamic> payload) {
    final value = payload['bookingNumber'];
    return value is String && value.isNotEmpty ? value : null;
  }

  int? _intValue(Object? value) => value is num ? value.toInt() : null;

  void _setUrgentActivity(String bookingNumber) {
    setState(() {
      _activeUrgentBooking = bookingNumber;
    });
    widget.onUrgentActivityChanged?.call(true);
  }

  void _clearUrgentActivity() {
    if (!_hasUrgentActivity) return;
    setState(() {
      _activeUrgentBooking = null;
      _customerDecisionExpiresAt = null;
      _awaitingPhase = null;
    });
    widget.onUrgentActivityChanged?.call(false);
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final status = await widget.repository.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
      _syncSocket(status);
      if (status.online) {
        await _loadCalls();
      } else {
        setState(() {
          _calls = null;
          _callsError = null;
        });
      }
    } on ApiException catch (error) {
      await _handleStatusError(error);
    } catch (_) {
      await _handleStatusError(const ApiException(ApiFailureKind.unknown));
    }
  }

  Future<void> _handleStatusError(ApiException error) async {
    if (error.kind == ApiFailureKind.unauthorized) {
      await widget.onUnauthorized();
      return;
    }
    if (!mounted) return;
    setState(() {
      _statusError = error;
      _loadingStatus = false;
    });
    widget.driverSocket?.disconnect();
  }

  Future<void> _loadCalls() async {
    if (_status?.online != true) return;
    setState(() {
      _loadingCalls = true;
      _callsError = null;
    });
    try {
      final calls = await widget.repository.getOpenCalls();
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _loadingCalls = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _callsError = error;
        _loadingCalls = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _callsError = const ApiException(ApiFailureKind.unknown);
        _loadingCalls = false;
      });
    }
  }

  Future<void> _setOnline(bool online) async {
    if (_changingOnline || _status == null) return;
    setState(() => _changingOnline = true);
    try {
      final status = online
          ? await widget.repository.goOnline()
          : await widget.repository.goOffline();
      if (!mounted) return;
      setState(() {
        _status = status;
        _changingOnline = false;
        if (!status.online) {
          _calls = null;
          _callsError = null;
          _showNewCallNotice = false;
        }
      });
      _syncSocket(status);
      if (status.online) await _loadCalls();
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() => _changingOnline = false);
      final l10n = AppLocalizations.of(context);
      _showMessage(
        error.errorCode == 'DRIVER_NOT_ELIGIBLE'
            ? l10n.errorDriverNotEligible
            : error.localizedMessage(l10n),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _changingOnline = false);
      final l10n = AppLocalizations.of(context);
      _showMessage(
        const ApiException(ApiFailureKind.unknown).localizedMessage(l10n),
      );
    }
  }

  Future<void> _selectCall(OpenCall call) async {
    if (_claiming.contains(call.bookingNumber)) return;
    final vehicles = call.compatibleVehicles;
    if (vehicles.isEmpty) {
      _showMessage(AppLocalizations.of(context).noApprovedVehicleForCall);
      return;
    }

    final vehicle = vehicles.length == 1
        ? vehicles.single
        : await showVehicleSelectSheet(context, vehicles);
    if (vehicle == null || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('claimConfirmDialog'),
        title: Text(l10n.acceptNewCallTitle),
        content: Text(l10n.acceptNewCallWithVehicle(vehicle.displayName)),
        actions: [
          TextButton(
            key: const Key('claimCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('claimConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.acceptCall),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _claim(call, vehicle);
    }
  }

  Future<void> _lockUrgentCall(OpenCall call) async {
    if (_lockingUrgent.contains(call.bookingNumber)) return;
    setState(() => _lockingUrgent.add(call.bookingNumber));
    try {
      final lock = await widget.repository.lockUrgentCall(call.bookingNumber);
      if (!mounted) return;
      _setUrgentActivity(call.bookingNumber);
      final result = await showUrgentEtaDialog(
        context: context,
        bookingNumber: call.bookingNumber,
        lockExpiresAt: lock.lockExpiresAt,
        minRequiredEtaMinutes: call.minRequiredEtaMinutes,
        onSubmit: (eta) =>
            widget.repository.submitUrgentEta(call.bookingNumber, eta),
      );
      if (!mounted) return;
      switch (result?.outcome) {
        case UrgentEtaDialogOutcome.submitted:
          final etaResult = result?.etaResult;
          setState(() {
            _customerDecisionExpiresAt = etaResult?.customerDecisionExpiresAt;
            _awaitingPhase = UrgentAwaitingPhase.awaiting;
            _hiddenUrgent.add(call.bookingNumber);
          });
        case UrgentEtaDialogOutcome.timedOut:
          _clearUrgentActivity();
          _showMessage(AppLocalizations.of(context).etaInputExpired);
          unawaited(_loadCalls());
        case UrgentEtaDialogOutcome.lostLock:
          _clearUrgentActivity();
          _showMessage(AppLocalizations.of(context).requestPassedToOtherDriver);
          unawaited(_loadCalls());
        case UrgentEtaDialogOutcome.leaveRequested:
          widget.onUrgentActivityChanged?.call(false);
          if (mounted) Navigator.of(context).maybePop();
        case null:
          break;
      }
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      final unavailable =
          error.kind == ApiFailureKind.urgentAlreadyLocked ||
          error.kind == ApiFailureKind.urgentNotBroadcasting;
      setState(() {
        if (unavailable) _hiddenUrgent.add(call.bookingNumber);
      });
      final l10n = AppLocalizations.of(context);
      _showMessage(
        error.kind == ApiFailureKind.urgentAlreadyLocked
            ? l10n.otherDriverAlreadyAcceptedCall
            : error.kind == ApiFailureKind.urgentNotBroadcasting
            ? l10n.urgentCallNoLongerAcceptable
            : error.localizedMessage(l10n),
      );
      if (unavailable) unawaited(_loadCalls());
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _showMessage(
        const ApiException(ApiFailureKind.unknown).localizedMessage(l10n),
      );
    } finally {
      if (mounted) {
        setState(() => _lockingUrgent.remove(call.bookingNumber));
      }
    }
  }

  Future<void> _claim(OpenCall call, CompatibleVehicle vehicle) async {
    setState(() => _claiming.add(call.bookingNumber));
    try {
      await widget.repository.claimOpenCall(
        call.bookingNumber,
        vehicle.driverVehicleId,
      );
      if (!mounted) return;
      setState(() {
        _claiming.remove(call.bookingNumber);
        final current = _calls;
        if (current != null) {
          _calls = OpenCallList(
            items: current.items
                .where((item) => item.bookingNumber != call.bookingNumber)
                .toList(growable: false),
            blockedReason: current.blockedReason,
            message: current.message,
          );
        }
      });
      _showMessage(AppLocalizations.of(context).callAssignmentCompleted);
      widget.onClaimed();
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      final alreadyClaimed =
          error.kind == ApiFailureKind.alreadyClaimed ||
          error.errorCode == 'ALREADY_ASSIGNED' ||
          error.errorCode == 'BOOKING_NOT_FOUND';
      setState(() {
        _claiming.remove(call.bookingNumber);
        if (alreadyClaimed && _calls != null) {
          final current = _calls!;
          _calls = OpenCallList(
            items: current.items
                .where((item) => item.bookingNumber != call.bookingNumber)
                .toList(growable: false),
            blockedReason: current.blockedReason,
            message: current.message,
          );
        }
      });
      final l10n = AppLocalizations.of(context);
      _showMessage(
        alreadyClaimed
            ? l10n.otherDriverClaimedCallFirst
            : error.kind == ApiFailureKind.bookingTimeConflict ||
                  error.errorCode == 'DRIVER_BOOKING_TIME_CONFLICT'
            ? l10n.errorBookingTimeConflict
            : error.localizedMessage(l10n),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _claiming.remove(call.bookingNumber));
      final l10n = AppLocalizations.of(context);
      _showMessage(
        const ApiException(ApiFailureKind.unknown).localizedMessage(l10n),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleScreenBack() async {
    if (!_hasUrgentActivity) {
      Navigator.of(context).maybePop();
      return;
    }
    final leave = await showUrgentLeaveConfirmation(context);
    if (leave == true && mounted) {
      widget.onUrgentActivityChanged?.call(false);
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !_hasUrgentActivity,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleScreenBack());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.newCallsTitle)),
        body: _loadingStatus
            ? const Center(
                key: Key('dispatchStatusLoading'),
                child: CircularProgressIndicator(),
              )
            : _statusError != null
            ? _StatusError(error: _statusError!, onRetry: _loadStatus)
            : Column(
                children: [
                  if (_awaitingPhase case final phase?)
                    UrgentAwaitingBanner(
                      bookingNumber: _activeUrgentBooking!,
                      customerDecisionExpiresAt: _customerDecisionExpiresAt,
                      phase: phase,
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      child: SwitchListTile(
                        key: const Key('onlineToggle'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        title: Text(
                          _status!.online ? l10n.online : l10n.offline,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        subtitle: Text(
                          _status!.online
                              ? l10n.canReceiveNewCalls
                              : l10n.newCallReceivingStopped,
                        ),
                        value: _status!.online,
                        onChanged: _changingOnline ? null : _setOnline,
                      ),
                    ),
                  ),
                  if (_showNewCallNotice && _status!.online)
                    Material(
                      key: const Key('newCallSocketNotice'),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.campaign_outlined),
                        title: Text(l10n.newCallsArrivedListRefreshed),
                        trailing: IconButton(
                          key: const Key('dismissNewCallSocketNotice'),
                          onPressed: () =>
                              setState(() => _showNewCallNotice = false),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _status!.online
                        ? _buildOnlineContent()
                        : Center(
                            key: const Key('offlineOpenCallsNotice'),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                l10n.goOnlineToSeeNewCalls,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildOnlineContent() {
    final l10n = AppLocalizations.of(context);
    if (_loadingCalls && _calls == null) {
      return const Center(
        key: Key('openCallsLoading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_callsError case final error?) {
      return Center(
        key: const Key('openCallsError'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.localizedMessage(l10n), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadCalls, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    final calls = _calls;
    final urgentCalls =
        calls?.items
            .where(
              (call) =>
                  call.isUrgentRequest &&
                  !_hiddenUrgent.contains(call.bookingNumber),
            )
            .toList(growable: false) ??
        const <OpenCall>[];
    final regularCalls =
        calls?.items
            .where((call) => !call.isUrgentRequest)
            .toList(growable: false) ??
        const <OpenCall>[];
    if (calls == null || (urgentCalls.isEmpty && regularCalls.isEmpty)) {
      return RefreshIndicator(
        onRefresh: _loadCalls,
        child: ListView(
          key: const Key('openCallsEmpty'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (calls?.blockedReason == 'UNPAID_SETTLEMENT')
              _SettlementBlockedCard(
                message:
                    calls?.message ?? l10n.unresolvedSettlementBlocksNewCalls,
                onOpenSettlement: widget.onOpenSettlement,
              ),
            const SizedBox(height: 140),
            const Icon(Icons.campaign_outlined, size: 52),
            const SizedBox(height: 12),
            Center(
              child: Text(
                calls?.message ?? l10n.noNewCallsAvailable,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCalls,
      child: ListView(
        key: const Key('openCallsList'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (calls.blockedReason == 'UNPAID_SETTLEMENT')
            _SettlementBlockedCard(
              message:
                  calls.message ?? l10n.unresolvedSettlementBlocksNewCalls,
              onOpenSettlement: widget.onOpenSettlement,
            ),
          if (urgentCalls.isNotEmpty)
            _UrgentCallsSection(
              calls: urgentCalls,
              locking: _lockingUrgent,
              onLock: _lockUrgentCall,
            ),
          if (regularCalls.isNotEmpty)
            ...regularCalls.map(
              (call) => _OpenCallCard(
                call: call,
                claiming: _claiming.contains(call.bookingNumber),
                onTap: () => _selectCall(call),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettlementBlockedCard extends StatelessWidget {
  const _SettlementBlockedCard({
    required this.message,
    required this.onOpenSettlement,
  });

  final String message;
  final VoidCallback? onOpenSettlement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('settlementBlockedBanner'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.unresolvedSettlementCheckRequired,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('openSettlementFromBlockedBanner'),
                onPressed: onOpenSettlement,
                child: Text(l10n.checkSettlement),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrgentCallsSection extends StatelessWidget {
  const _UrgentCallsSection({
    required this.calls,
    required this.locking,
    required this.onLock,
  });

  final List<OpenCall> calls;
  final Set<String> locking;
  final ValueChanged<OpenCall> onLock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('urgentCallsSection'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.tertiary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.priority_high),
                const SizedBox(width: 6),
                Text(
                  l10n.urgentCallLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ...calls.map(
            (call) => _UrgentCallCard(
              call: call,
              locking: locking.contains(call.bookingNumber),
              onLock: () => onLock(call),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgentCallCard extends StatelessWidget {
  const _UrgentCallCard({
    required this.call,
    required this.locking,
    required this.onLock,
  });

  final OpenCall call;
  final bool locking;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheduled =
        _formatDateTime(call.scheduledPickupAt) ??
        '${call.pickupDate} ${call.pickupTime}';
    final meetingGate = resolveBkkAirportPickupMeetingGate(
      serviceTypeCode: call.serviceTypeCode,
      nameSignRequested: call.nameSignRequested,
      pickupCandidates: [call.origin],
    );
    final amount = call.customerPaymentAmount ?? call.amount;
    final currency = call.customerPaymentCurrency ?? call.currency;
    final luggage = <String>[
      if (call.luggage.carriers20Inch > 0)
        l10n.carriers20InchCount(call.luggage.carriers20Inch),
      if (call.luggage.carriers24InchPlus > 0)
        l10n.carriers24InchPlusCount(call.luggage.carriers24InchPlus),
      if (call.luggage.golfBags > 0) l10n.golfBagCount(call.luggage.golfBags),
      ?call.luggage.specialItems,
    ].join(' · ');
    return Card(
      key: Key('urgentCall-${call.bookingNumber}'),
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _PickupRequestedTimeTitle(timeText: scheduled),
                ),
                Chip(label: Text(l10n.urgentChip)),
              ],
            ),
            if (meetingGate != null)
              Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  key: Key('openCallGate-${call.bookingNumber}'),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.meeting_room_outlined, size: 16),
                  label: Text(l10n.meetingGateNumber(int.parse(meetingGate))),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _OpenCallLocationText(
                    location: call.pickupLocation,
                    fallbackAddress: call.origin,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('→'),
                ),
                Expanded(
                  child: _OpenCallLocationText(
                    location: call.destinationLocation,
                    fallbackAddress: call.destination,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${call.serviceTypeName} · ${call.vehicleTypeName} · '
              '${l10n.passengersCount(call.passengerCount)}',
            ),
            const SizedBox(height: 6),
            Text('$amount $currency'),
            if (luggage.isNotEmpty) Text(luggage),
            if (call.minRequiredEtaMinutes case final minimum?) ...[
              const SizedBox(height: 8),
              Text(
                l10n.previousRejectionRequiresEtaUnder(minimum),
                key: Key('urgentMinEta-${call.bookingNumber}'),
              ),
            ],
            _BookingCreatedAtText(
              key: Key('openCallCreatedAt-${call.bookingNumber}'),
              createdAt: call.createdAt,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('urgentAccept-${call.bookingNumber}'),
                onPressed: locking ? null : onLock,
                icon: locking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(l10n.accept),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('dispatchStatusError'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.localizedMessage(l10n), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}

class _OpenCallCard extends StatelessWidget {
  const _OpenCallCard({
    required this.call,
    required this.claiming,
    required this.onTap,
  });

  final OpenCall call;
  final bool claiming;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheduled = _formatDateTime(call.scheduledPickupAt);
    final meetingGate = resolveBkkAirportPickupMeetingGate(
      serviceTypeCode: call.serviceTypeCode,
      nameSignRequested: call.nameSignRequested,
      pickupCandidates: [call.origin],
    );
    final matchLabel = call.isExactVehicleMatch
        ? l10n.vehicleExactMatch(call.vehicleMatchType)
        : l10n.vehicleCompatibleUpgrade(call.vehicleMatchType);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('openCall-${call.bookingNumber}'),
        onTap: claiming ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PickupRequestedTimeTitle(
                      timeText:
                          scheduled ?? '${call.pickupDate} ${call.pickupTime}',
                    ),
                  ),
                  Chip(
                    key: Key('vehicleMatch-${call.bookingNumber}'),
                    label: Text(matchLabel),
                  ),
                ],
              ),
              if (meetingGate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Chip(
                    key: Key('openCallGate-${call.bookingNumber}'),
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.meeting_room_outlined, size: 16),
                    label: Text(l10n.meetingGateNumber(int.parse(meetingGate))),
                  ),
                ),
              const SizedBox(height: 10),
              _OpenCallLocationText(
                location: call.pickupLocation,
                fallbackAddress: call.origin,
                key: Key('openCallOrigin-${call.bookingNumber}'),
              ),
              const SizedBox(height: 6),
              _OpenCallLocationText(
                location: call.destinationLocation,
                fallbackAddress: call.destination,
                key: Key('openCallDestination-${call.bookingNumber}'),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.vehicleTypeAndPassengers(
                  call.vehicleTypeName,
                  call.passengerCount,
                ),
              ),
              _BookingCreatedAtText(
                key: Key('openCallCreatedAt-${call.bookingNumber}'),
                createdAt: call.createdAt,
              ),
              if (claiming) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PickupRequestedTimeTitle extends StatelessWidget {
  const _PickupRequestedTimeTitle({required this.timeText});

  final String timeText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        style: theme.textTheme.titleMedium,
        children: [
          TextSpan(
            text: '출발 요청시간 : ',
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          TextSpan(
            text: timeText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _BookingCreatedAtText extends StatelessWidget {
  const _BookingCreatedAtText({super.key, required this.createdAt});

  final String? createdAt;

  @override
  Widget build(BuildContext context) {
    final formatted = formatBookingDateTime(createdAt);
    if (formatted == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '예약시간 : $formatted',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String? _formatDateTime(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final hasTimeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  final bangkok = hasTimeZone
      ? parsed.toUtc().add(const Duration(hours: 7))
      : parsed;
  return '${bangkok.year.toString().padLeft(4, '0')}-'
      '${bangkok.month.toString().padLeft(2, '0')}-'
      '${bangkok.day.toString().padLeft(2, '0')} '
      '${bangkok.hour.toString().padLeft(2, '0')}:'
      '${bangkok.minute.toString().padLeft(2, '0')}';
}

class _OpenCallLocationText extends StatelessWidget {
  const _OpenCallLocationText({
    super.key,
    required this.location,
    required this.fallbackAddress,
  });

  final BookingLocation? location;
  final String fallbackAddress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final placeStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    );
    final nameTh = location?.nameTh?.trim();
    final name = location?.name?.trim();
    final hasStructuredName = location != null &&
        ((nameTh != null && nameTh.isNotEmpty) ||
            (name != null && name.isNotEmpty));

    if (hasStructuredName) {
      final lines = parseBookingLocation(location!);
      if (lines.hasSeparateAddress) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lines.placeName!, style: placeStyle),
            Text(lines.addressLine!),
          ],
        );
      }
      if (lines.hasPlaceName) {
        return Text(lines.placeName!, style: placeStyle);
      }
      if (lines.hasAddressLine) {
        return Text(lines.addressLine!);
      }
      return Text(l10n.noLocationInfo);
    }

    return Text(
      AirportLabelResolver.displayLabelFor(fallbackAddress),
      style: placeStyle,
    );
  }
}
