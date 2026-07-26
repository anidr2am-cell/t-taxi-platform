import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../data/dispatch_models.dart';

typedef UrgentEtaSubmitter =
    Future<UrgentCallEtaResult> Function(int etaMinutes);

enum UrgentEtaDialogOutcome { submitted, timedOut, lostLock, leaveRequested }

class UrgentEtaDialogResult {
  const UrgentEtaDialogResult(this.outcome, {this.etaResult});

  final UrgentEtaDialogOutcome outcome;
  final UrgentCallEtaResult? etaResult;
}

Future<UrgentEtaDialogResult?> showUrgentEtaDialog({
  required BuildContext context,
  required String bookingNumber,
  required String? lockExpiresAt,
  required int? minRequiredEtaMinutes,
  required UrgentEtaSubmitter onSubmit,
}) {
  return showDialog<UrgentEtaDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UrgentEtaDialog(
      bookingNumber: bookingNumber,
      lockExpiresAt: lockExpiresAt,
      minRequiredEtaMinutes: minRequiredEtaMinutes,
      onSubmit: onSubmit,
    ),
  );
}

class _UrgentEtaDialog extends StatefulWidget {
  const _UrgentEtaDialog({
    required this.bookingNumber,
    required this.lockExpiresAt,
    required this.minRequiredEtaMinutes,
    required this.onSubmit,
  });

  final String bookingNumber;
  final String? lockExpiresAt;
  final int? minRequiredEtaMinutes;
  final UrgentEtaSubmitter onSubmit;

  @override
  State<_UrgentEtaDialog> createState() => _UrgentEtaDialogState();
}

class _UrgentEtaDialogState extends State<_UrgentEtaDialog> {
  final _controller = TextEditingController();
  Timer? _timer;
  late DateTime _deadline;
  late Duration _remaining;
  bool _submitting = false;
  bool _expired = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _deadline =
        parseUrgentDeadline(widget.lockExpiresAt) ??
        DateTime.now().add(const Duration(minutes: 3));
    _remaining = remainingUntil(_deadline);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (_remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _expire());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _expired) return;
    final remaining = remainingUntil(_deadline);
    setState(() => _remaining = remaining);
    if (remaining == Duration.zero) _expire();
  }

  void _expire() {
    if (!mounted || _expired) return;
    _expired = true;
    _timer?.cancel();
    Navigator.of(
      context,
    ).pop(const UrgentEtaDialogResult(UrgentEtaDialogOutcome.timedOut));
  }

  Future<void> _submit() async {
    if (_submitting || _expired) return;
    final eta = int.tryParse(_controller.text);
    if (eta == null || eta < 1) {
      setState(() => _inlineError = '1분 이상의 정수를 입력해 주세요.');
      return;
    }
    final minimum = widget.minRequiredEtaMinutes;
    if (minimum != null && eta >= minimum) {
      setState(() => _inlineError = '$minimum분 미만으로 입력해 주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    try {
      final result = await widget.onSubmit(eta);
      if (!mounted) return;
      Navigator.of(context).pop(
        UrgentEtaDialogResult(
          UrgentEtaDialogOutcome.submitted,
          etaResult: result,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.kind == ApiFailureKind.urgentEtaExpired) {
        Navigator.of(
          context,
        ).pop(const UrgentEtaDialogResult(UrgentEtaDialogOutcome.timedOut));
        return;
      }
      if (error.kind == ApiFailureKind.urgentNotLockedDriver ||
          error.kind == ApiFailureKind.urgentNotLocked) {
        Navigator.of(
          context,
        ).pop(const UrgentEtaDialogResult(UrgentEtaDialogOutcome.lostLock));
        return;
      }
      final serverMinimum = _minimumFrom(error.errors);
      setState(() {
        _submitting = false;
        _inlineError =
            error.kind == ApiFailureKind.urgentEtaNotFastEnough &&
                serverMinimum != null
            ? '$serverMinimum분 미만으로 입력해 주세요.'
            : error.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _inlineError = const ApiException(ApiFailureKind.unknown).userMessage;
      });
    }
  }

  Future<void> _requestLeave() async {
    final leave = await showUrgentLeaveConfirmation(context);
    if (leave == true && mounted) {
      Navigator.of(
        context,
      ).pop(const UrgentEtaDialogResult(UrgentEtaDialogOutcome.leaveRequested));
    }
  }

  @override
  Widget build(BuildContext context) {
    final warning = _remaining <= const Duration(seconds: 30);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestLeave());
      },
      child: AlertDialog(
        key: const Key('urgentEtaDialog'),
        title: const Text('도착 예상 시간 입력'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '남은 시간 ${formatUrgentCountdown(_remaining)}',
              key: const Key('urgentEtaCountdown'),
              style: TextStyle(
                color: warning
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.minRequiredEtaMinutes case final minimum?) ...[
              const SizedBox(height: 8),
              Text(
                '이전 거절로 $minimum분 미만 ETA가 필요합니다.',
                key: const Key('urgentEtaMinimumHint'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('urgentEtaInput'),
              controller: _controller,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'ETA (분)',
                errorText: _inlineError,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          FilledButton(
            key: const Key('urgentEtaSubmit'),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('제출'),
          ),
        ],
      ),
    );
  }
}

int? _minimumFrom(List<Map<String, dynamic>> errors) {
  if (errors.isEmpty) return null;
  final value = errors.first['minRequiredEtaMinutes'];
  return value is num ? value.toInt() : null;
}

DateTime? parseUrgentDeadline(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final hasZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(normalized);
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) return null;
  if (hasZone) return parsed.toUtc();
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour - 7,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

Duration remainingUntil(DateTime deadline, [DateTime? now]) {
  final remaining = deadline.difference((now ?? DateTime.now()).toUtc());
  return remaining.isNegative ? Duration.zero : remaining;
}

String formatUrgentCountdown(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 359999);
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${rest.toString().padLeft(2, '0')}';
}

Future<bool?> showUrgentLeaveConfirmation(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('urgentLeaveDialog'),
      title: const Text('진행 중인 긴급 협상'),
      content: const Text(
        '진행 중인 긴급 협상이 있습니다. 그래도 나가시겠습니까?\n'
        '서버의 잠금은 즉시 해제되지 않으며, ETA를 제출하지 않으면 '
        '3분 이내 자동으로 취소됩니다.',
      ),
      actions: [
        TextButton(
          key: const Key('urgentLeaveStay'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('계속 진행'),
        ),
        FilledButton(
          key: const Key('urgentLeaveConfirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('나가기'),
        ),
      ],
    ),
  );
}
