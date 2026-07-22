import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../services/driver_api_service.dart';
import '../utils/driver_backend_datetime.dart';

class DriverUrgentEtaDialogResult {
  const DriverUrgentEtaDialogResult({
    required this.submitted,
    this.customerDecisionExpiresAt,
    this.timedOut = false,
  });

  final bool submitted;
  final String? customerDecisionExpiresAt;
  final bool timedOut;
}

Future<DriverUrgentEtaDialogResult?> showDriverUrgentEtaDialog({
  required BuildContext context,
  required DriverApiService api,
  required String bookingNumber,
  required String lockExpiresAt,
  int? minRequiredEtaMinutes,
}) {
  return showDialog<DriverUrgentEtaDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DriverUrgentEtaDialog(
      api: api,
      bookingNumber: bookingNumber,
      lockExpiresAt: lockExpiresAt,
      minRequiredEtaMinutes: minRequiredEtaMinutes,
    ),
  );
}

class _DriverUrgentEtaDialog extends StatefulWidget {
  const _DriverUrgentEtaDialog({
    required this.api,
    required this.bookingNumber,
    required this.lockExpiresAt,
    this.minRequiredEtaMinutes,
  });

  final DriverApiService api;
  final String bookingNumber;
  final String lockExpiresAt;
  final int? minRequiredEtaMinutes;

  @override
  State<_DriverUrgentEtaDialog> createState() => _DriverUrgentEtaDialogState();
}

class _DriverUrgentEtaDialogState extends State<_DriverUrgentEtaDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _submitError;
  Duration _remaining = Duration.zero;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _updateRemaining() {
    if (!mounted) return;
    final remaining = remainingUntilBackendServiceDateTime(
      widget.lockExpiresAt,
      fallback: const Duration(minutes: 3),
    );
    setState(() => _remaining = remaining);
    if (_remaining <= Duration.zero) {
      _countdownTimer?.cancel();
      Navigator.of(context).pop(
        const DriverUrgentEtaDialogResult(submitted: false, timedOut: true),
      );
    }
  }

  String? _inlineErrorMessage(Object err, AppLocalizations l10n) {
    if (err is DriverApiException) {
      return switch (err.errorCode) {
        'URGENT_ETA_NOT_FAST_ENOUGH' => l10n.t('driver_urgent_eta_not_fast_enough'),
        'URGENT_ETA_WINDOW_EXPIRED' => l10n.t('driver_urgent_eta_lock_expired'),
        'URGENT_ETA_INVALID' => l10n.t('driver_urgent_eta_invalid'),
        _ => driverApiErrorMessage(
          message: err.message,
          errorCode: err.errorCode,
          languageCode: Localizations.localeOf(context).languageCode,
        ),
      };
    }
    return userFacingError(err, fallback: l10n.t('driver_action_failed'));
  }

  Future<void> _submit() async {
    if (_submitting || _remaining <= Duration.zero) return;
    if (!_formKey.currentState!.validate()) return;

    final etaMinutes = int.parse(_controller.text.trim());
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = await widget.api.submitUrgentCallEta(
        widget.bookingNumber,
        etaMinutes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        DriverUrgentEtaDialogResult(
          submitted: true,
          customerDecisionExpiresAt:
              result['customerDecisionExpiresAt']?.toString(),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = _inlineErrorMessage(err, context.l10n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final minEta = widget.minRequiredEtaMinutes;

    return AlertDialog(
      title: Text(l10n.t('driver_urgent_eta_dialog_title')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.t('driver_urgent_eta_dialog_message')),
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                l10n
                    .t('driver_urgent_eta_countdown')
                    .replaceAll('{time}', formatCountdownMmSs(_remaining)),
                style: TextStyle(
                  color: _remaining.inSeconds <= 30
                      ? AppTokens.error
                      : AppTokens.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (minEta != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  l10n
                      .t('driver_urgent_min_eta_hint')
                      .replaceAll('{minutes}', '$minEta'),
                  style: const TextStyle(color: AppTokens.textSecondary),
                ),
              ],
              const SizedBox(height: AppTokens.spaceMd),
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.t('driver_urgent_eta_minutes_label'),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return l10n.t('driver_urgent_eta_invalid');
                  }
                  if (minEta != null && parsed >= minEta) {
                    return l10n
                        .t('driver_urgent_min_eta_hint')
                        .replaceAll('{minutes}', '$minEta');
                  }
                  return null;
                },
              ),
              if (_submitError != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  _submitError!,
                  style: const TextStyle(color: AppTokens.error, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting || _remaining <= Duration.zero ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.t('driver_urgent_eta_submit')),
        ),
      ],
    );
  }
}
