import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/driver_urgent_negotiation_controller.dart';
import '../utils/driver_backend_datetime.dart';

class DriverUrgentNegotiationBanner extends StatefulWidget {
  const DriverUrgentNegotiationBanner({super.key, this.bookingNumber});

  final String? bookingNumber;

  @override
  State<DriverUrgentNegotiationBanner> createState() =>
      _DriverUrgentNegotiationBannerState();
}

class _DriverUrgentNegotiationBannerState
    extends State<DriverUrgentNegotiationBanner> {
  final _controller = DriverUrgentNegotiationController.instance;
  Timer? _tickTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _syncTimer();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _tickTimer?.cancel();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncTimer();
    setState(() {});
  }

  void _syncTimer() {
    _tickTimer?.cancel();
    _updateRemaining();
    final state = _controller.state;
    if (!state.matchesBooking(widget.bookingNumber) ||
        state.phase != DriverUrgentNegotiationBannerPhase.awaitingCustomer) {
      return;
    }
    _tickTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  void _updateRemaining() {
    if (!mounted) return;
    final state = _controller.state;
    if (!state.matchesBooking(widget.bookingNumber) ||
        state.phase != DriverUrgentNegotiationBannerPhase.awaitingCustomer) {
      setState(() => _remaining = Duration.zero);
      return;
    }
    final expiresAt = parseBackendServiceDateTime(state.expiresAt);
    if (expiresAt == null) {
      setState(() => _remaining = const Duration(minutes: 2));
      return;
    }
    final diff = expiresAt.difference(DateTime.now());
    final remaining = diff.isNegative ? Duration.zero : diff;
    setState(() => _remaining = remaining);
    if (remaining <= Duration.zero) {
      _tickTimer?.cancel();
      _controller.showMessagePhase(
        state.bookingNumber!,
        DriverUrgentNegotiationBannerPhase.roundEnded,
      );
    }
  }

  String _messageKey(DriverUrgentNegotiationBannerPhase phase) {
    return switch (phase) {
      DriverUrgentNegotiationBannerPhase.awaitingCustomer =>
        'driver_urgent_awaiting_customer',
      DriverUrgentNegotiationBannerPhase.confirmed => 'driver_urgent_confirmed',
      DriverUrgentNegotiationBannerPhase.cancelled => 'driver_urgent_cancelled',
      DriverUrgentNegotiationBannerPhase.roundEnded =>
        'driver_urgent_round_ended',
      DriverUrgentNegotiationBannerPhase.etaLockExpired =>
        'driver_urgent_eta_lock_expired',
      DriverUrgentNegotiationBannerPhase.hidden => '',
    };
  }

  AppStatusTone _tone(DriverUrgentNegotiationBannerPhase phase) {
    return switch (phase) {
      DriverUrgentNegotiationBannerPhase.awaitingCustomer => AppStatusTone.info,
      DriverUrgentNegotiationBannerPhase.confirmed => AppStatusTone.success,
      DriverUrgentNegotiationBannerPhase.cancelled ||
      DriverUrgentNegotiationBannerPhase.roundEnded ||
      DriverUrgentNegotiationBannerPhase.etaLockExpired => AppStatusTone.warning,
      DriverUrgentNegotiationBannerPhase.hidden => AppStatusTone.neutral,
    };
  }

  Color _background(DriverUrgentNegotiationBannerPhase phase) {
    return switch (phase) {
      DriverUrgentNegotiationBannerPhase.awaitingCustomer => AppTokens.infoLight,
      DriverUrgentNegotiationBannerPhase.confirmed => AppTokens.successLight,
      DriverUrgentNegotiationBannerPhase.cancelled ||
      DriverUrgentNegotiationBannerPhase.roundEnded ||
      DriverUrgentNegotiationBannerPhase.etaLockExpired =>
        AppTokens.warning.withValues(alpha: 0.12),
      DriverUrgentNegotiationBannerPhase.hidden => AppTokens.surface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    if (!state.matchesBooking(widget.bookingNumber) ||
        state.phase == DriverUrgentNegotiationBannerPhase.hidden) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final time = formatCountdownMmSs(_remaining);
    final message = l10n
        .t(_messageKey(state.phase))
        .replaceAll('{time}', time)
        .replaceAll('{bookingNumber}', state.bookingNumber ?? '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceMd,
        0,
      ),
      child: AppUi.surfaceCard(
        backgroundColor: _background(state.phase),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: _tone(state.phase) == AppStatusTone.success
                      ? AppTokens.success
                      : AppTokens.textPrimary,
                ),
              ),
            ),
            if (state.phase != DriverUrgentNegotiationBannerPhase.awaitingCustomer)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _controller.clear(bookingNumber: state.bookingNumber),
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
