import 'dart:async';

import 'package:flutter/material.dart';

import 'urgent_eta_dialog.dart';

enum UrgentAwaitingPhase { awaiting, checking, confirmed }

class UrgentAwaitingBanner extends StatefulWidget {
  const UrgentAwaitingBanner({
    super.key,
    required this.bookingNumber,
    required this.customerDecisionExpiresAt,
    required this.phase,
  });

  final String bookingNumber;
  final String? customerDecisionExpiresAt;
  final UrgentAwaitingPhase phase;

  @override
  State<UrgentAwaitingBanner> createState() => _UrgentAwaitingBannerState();
}

class _UrgentAwaitingBannerState extends State<UrgentAwaitingBanner> {
  Timer? _timer;
  late DateTime _deadline;
  Duration _remaining = Duration.zero;
  bool _localChecking = false;

  @override
  void initState() {
    super.initState();
    _resetDeadline();
  }

  @override
  void didUpdateWidget(covariant UrgentAwaitingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerDecisionExpiresAt !=
        widget.customerDecisionExpiresAt) {
      _resetDeadline();
    } else if (widget.phase != UrgentAwaitingPhase.awaiting) {
      _timer?.cancel();
    }
  }

  void _resetDeadline() {
    _timer?.cancel();
    _deadline =
        parseUrgentDeadline(widget.customerDecisionExpiresAt) ??
        DateTime.now().add(const Duration(minutes: 2));
    _remaining = remainingUntil(_deadline);
    _localChecking = _remaining == Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || widget.phase != UrgentAwaitingPhase.awaiting) return;
    final remaining = remainingUntil(_deadline);
    setState(() {
      _remaining = remaining;
      if (remaining == Duration.zero) _localChecking = true;
    });
    if (remaining == Duration.zero) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.phase;
    final confirmed = phase == UrgentAwaitingPhase.confirmed;
    final checking = phase == UrgentAwaitingPhase.checking || _localChecking;
    final color = confirmed
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.tertiaryContainer;
    final icon = confirmed ? Icons.check_circle : Icons.schedule;
    final message = confirmed
        ? '고객이 확인했습니다. 예약이 배정되었습니다.'
        : checking
        ? '라운드 종료 확인 중...'
        : '고객 확인 대기 중 '
              '(남은 시간 ${formatUrgentCountdown(_remaining)})';

    return Material(
      key: const Key('urgentAwaitingBanner'),
      color: color,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          leading: Icon(icon),
          title: Text(message, key: const Key('urgentAwaitingMessage')),
          subtitle: Text(widget.bookingNumber),
        ),
      ),
    );
  }
}
