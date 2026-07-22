import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_create_result.dart';
import '../models/guest_booking_lookup_result.dart';
import '../models/urgent_negotiation_status.dart';
import '../services/booking_api_service.dart';
import '../services/customer_urgent_negotiation_socket_service.dart';
import '../services/guest_booking_lookup_service.dart';

enum UrgentFlowPhase {
  searching,
  etaProposed,
  retryPrompt,
  confirmed,
  exhausted,
}

class UrgentBookingFlowPage extends StatefulWidget {
  const UrgentBookingFlowPage({
    super.key,
    required this.result,
    this.customerPhone,
    this.apiService,
    this.socketService,
    this.lookupService,
  });

  final BookingCreateResult result;
  final String? customerPhone;
  final BookingApiService? apiService;
  final CustomerUrgentNegotiationSocketService? socketService;
  final GuestBookingLookupService? lookupService;

  @visibleForTesting
  static UrgentFlowPhase phaseFromStatus(UrgentNegotiationStatus status) {
    if (status.isConfirmed || status.bookingStatus == 'DRIVER_ASSIGNED') {
      return UrgentFlowPhase.confirmed;
    }
    if (status.isCancelled ||
        status.closedReason == 'URGENT_NEGOTIATION_EXHAUSTED' ||
        status.bookingStatus == 'CANCELLED') {
      return UrgentFlowPhase.exhausted;
    }
    if (status.isAwaitingCustomer && status.proposedEtaMinutes != null) {
      return UrgentFlowPhase.etaProposed;
    }
    return UrgentFlowPhase.searching;
  }

  @override
  State<UrgentBookingFlowPage> createState() => _UrgentBookingFlowPageState();
}

class _UrgentBookingFlowPageState extends State<UrgentBookingFlowPage> {
  late final BookingApiService _api;
  late final CustomerUrgentNegotiationSocketService _socket;
  late final GuestBookingLookupService _lookup;

  UrgentFlowPhase _phase = UrgentFlowPhase.searching;
  UrgentNegotiationStatus? _status;
  int? _proposedEtaMinutes;
  String? _errorMessage;
  bool _busy = false;
  Timer? _pollTimer;

  String? get _guestToken => widget.result.guestAccessToken;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? BookingApiService();
    _socket = widget.socketService ?? CustomerUrgentNegotiationSocketService();
    _lookup = widget.lookupService ?? GuestBookingLookupService();
    _startRealtime();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket.disconnect();
    super.dispose();
  }

  Future<void> _startRealtime() async {
    final token = _guestToken;
    _socket.onEtaProposed = _handleEtaProposed;
    _socket.onConfirmed = (_) => _refreshStatus(forcePhase: UrgentFlowPhase.confirmed);
    _socket.onCancelled = (_) => _setPhase(UrgentFlowPhase.exhausted);
    _socket.onExpired = (_) => _refreshStatus(forcePhase: UrgentFlowPhase.searching);
    _socket.onSubscribed = (payload) {
      final status = UrgentNegotiationStatus.fromJson(payload);
      _applyStatus(status);
    };

    final usingInjectedSocket = widget.socketService != null;
    if (!usingInjectedSocket) {
      _socket.connect(guestAccessToken: token);
      await _socket.subscribe(widget.result.bookingNumber);
    }
    await _refreshStatus();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _refreshStatus());
  }

  void _handleEtaProposed(Map<String, dynamic> payload) {
    final eta = payload['etaMinutes'];
    setState(() {
      _proposedEtaMinutes = eta is int ? eta : int.tryParse('$eta');
      _phase = UrgentFlowPhase.etaProposed;
      _errorMessage = null;
    });
    _refreshStatus();
  }

  Future<void> _refreshStatus({UrgentFlowPhase? forcePhase}) async {
    final token = _guestToken;
    if (token == null || token.isEmpty) return;
    try {
      final status = await _api.getUrgentNegotiation(
        bookingNumber: widget.result.bookingNumber,
        guestAccessToken: token,
      );
      if (!mounted) return;
      _applyStatus(status, forcePhase: forcePhase);
    } catch (_) {
      // Polling failures are non-fatal while socket events may still arrive.
    }
  }

  void _applyStatus(UrgentNegotiationStatus status, {UrgentFlowPhase? forcePhase}) {
    setState(() {
      _status = status;
      _proposedEtaMinutes ??= status.proposedEtaMinutes;
      if (forcePhase != null) {
        _phase = forcePhase;
      } else if (_phase != UrgentFlowPhase.retryPrompt) {
        _phase = UrgentBookingFlowPage.phaseFromStatus(status);
      }
      if (_phase == UrgentFlowPhase.etaProposed) {
        _proposedEtaMinutes = status.proposedEtaMinutes ?? _proposedEtaMinutes;
      }
    });
  }

  void _setPhase(UrgentFlowPhase phase) {
    if (!mounted) return;
    setState(() => _phase = phase);
  }

  Future<void> _submitDecision(String decision) async {
    final token = _guestToken;
    if (token == null || token.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final result = await _api.submitUrgentDecision(
        bookingNumber: widget.result.bookingNumber,
        decision: decision,
        guestAccessToken: token,
      );
      if (!mounted) return;
      if (decision == 'ACCEPT') {
        _setPhase(UrgentFlowPhase.confirmed);
      } else if (result.closedReason == 'URGENT_NEGOTIATION_EXHAUSTED' ||
          result.bookingStatus == 'CANCELLED') {
        _setPhase(UrgentFlowPhase.exhausted);
      } else {
        _setPhase(UrgentFlowPhase.retryPrompt);
      }
      await _refreshStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = userFacingError(e, fallback: 'ui_action_failed');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelBooking() async {
    final phone = widget.customerPhone?.trim();
    final token = _guestToken;
    if (phone == null || phone.isEmpty || token == null || token.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final booking = GuestBookingLookupResult.fromCreateSummary(
        bookingId: widget.result.bookingId,
        bookingNumber: widget.result.bookingNumber,
        status: widget.result.status,
        totalAmount: widget.result.totalAmount,
        currency: widget.result.currency,
        paymentMethod: widget.result.paymentMethod,
        guestAccessToken: token,
        customerPhone: phone,
        serviceTypeName: '',
        originAddress: '',
        destinationAddress: '',
      );
      await _lookup.cancelBooking(booking: booking);
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = userFacingError(e, fallback: 'ui_action_failed');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('customer_urgent_flow_title')),
        automaticallyImplyLeading: _phase != UrgentFlowPhase.searching,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: AppUi.pagePadding(context),
            child: _buildBody(l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_errorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.errorState(message: l10n.t(_errorMessage!)),
          const SizedBox(height: 12),
          _buildPhaseContent(l10n),
        ],
      );
    }
    return _buildPhaseContent(l10n);
  }

  Widget _buildPhaseContent(AppLocalizations l10n) {
    switch (_phase) {
      case UrgentFlowPhase.searching:
        return _messageCard(
          icon: Icons.search,
          title: l10n.t('customer_urgent_searching_title'),
          body: l10n.t('customer_urgent_searching_body'),
          trailing: const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      case UrgentFlowPhase.etaProposed:
        final eta = _proposedEtaMinutes ?? _status?.proposedEtaMinutes ?? 0;
        return _messageCard(
          icon: Icons.schedule,
          title: l10n
              .t('customer_urgent_eta_title')
              .replaceAll('{minutes}', '$eta'),
          body: l10n.t('customer_urgent_eta_body'),
          actions: [
            FilledButton(
              onPressed: _busy ? null : () => _submitDecision('ACCEPT'),
              child: Text(l10n.t('customer_urgent_accept_eta')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _submitDecision('REJECT'),
              child: Text(l10n.t('customer_urgent_reject_eta')),
            ),
          ],
        );
      case UrgentFlowPhase.retryPrompt:
        return _messageCard(
          icon: Icons.refresh,
          title: l10n.t('customer_urgent_retry_title'),
          body: l10n.t('customer_urgent_retry_body'),
          actions: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _setPhase(UrgentFlowPhase.searching),
              child: Text(l10n.t('customer_urgent_retry_accept')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _cancelBooking,
              child: Text(l10n.t('customer_urgent_retry_cancel')),
            ),
          ],
        );
      case UrgentFlowPhase.confirmed:
        return _messageCard(
          icon: Icons.check_circle_outline,
          title: l10n.t('customer_urgent_confirmed_title'),
          body: l10n.t('customer_urgent_confirmed_body'),
          actions: [
            FilledButton(
              onPressed: _goHome,
              child: Text(l10n.t('customer_urgent_go_home')),
            ),
          ],
        );
      case UrgentFlowPhase.exhausted:
        return _messageCard(
          icon: Icons.info_outline,
          title: l10n.t('customer_urgent_exhausted_title'),
          body: l10n.t('customer_urgent_exhausted_body'),
          actions: [
            FilledButton(
              onPressed: _goHome,
              child: Text(l10n.t('customer_urgent_go_home')),
            ),
          ],
        );
    }
  }

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String body,
    List<Widget>? actions,
    Widget? trailing,
  }) {
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 40, color: AppTokens.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.5,
            ),
          ),
          if (trailing != null) trailing,
          if (actions != null) ...[
            const SizedBox(height: 20),
            ...actions,
          ],
        ],
      ),
    );
  }
}
