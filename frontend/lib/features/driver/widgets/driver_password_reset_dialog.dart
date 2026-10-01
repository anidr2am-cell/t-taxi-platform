import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../services/driver_api_service.dart';

Future<void> showDriverPasswordResetDialog(
  BuildContext context, {
  required DriverApiService api,
  String initialIdentifier = '',
}) => showDialog<void>(
  context: context,
  builder: (_) => _DriverPasswordResetDialog(
    api: api,
    initialIdentifier: initialIdentifier,
  ),
);

class _DriverPasswordResetDialog extends StatefulWidget {
  const _DriverPasswordResetDialog({
    required this.api,
    required this.initialIdentifier,
  });
  final DriverApiService api;
  final String initialIdentifier;
  @override
  State<_DriverPasswordResetDialog> createState() =>
      _DriverPasswordResetDialogState();
}

class _DriverPasswordResetDialogState
    extends State<_DriverPasswordResetDialog> {
  late final TextEditingController _identifier = TextEditingController(
    text: widget.initialIdentifier,
  );
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _setError(String message) => setState(() => _error = message);
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) _setError(context.l10n.t('driver_reset_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request() async {
    if (_identifier.text.trim().length < 5) {
      _setError(context.l10n.t('driver_reset_identifier_required'));
      return;
    }
    await _run(() async {
      await widget.api.requestPasswordReset(_identifier.text.trim());
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _reset() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      _setError(context.l10n.t('driver_reset_code_invalid'));
      return;
    }
    if (_password.text.length < 8) {
      _setError(context.l10n.t('driver_reset_password_min'));
      return;
    }
    if (_password.text != _confirm.text) {
      _setError(context.l10n.t('driver_reset_password_mismatch'));
      return;
    }
    await _run(() async {
      await widget.api.confirmPasswordReset(
        identifier: _identifier.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('driver_reset_success'))),
      );
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.t('driver_reset_title')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.t(
              _codeSent
                  ? 'driver_reset_code_help'
                  : 'driver_reset_request_help',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('driverResetIdentifierField'),
            controller: _identifier,
            enabled: !_codeSent && !_loading,
            decoration: InputDecoration(
              labelText: context.l10n.t('driver_reset_identifier'),
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('driverResetCodeField'),
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: context.l10n.t('driver_reset_code'),
              ),
            ),
            TextField(
              key: const Key('driverResetPasswordField'),
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.t('driver_reset_new_password'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('driverResetPasswordConfirmField'),
              controller: _confirm,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.t('driver_reset_confirm_password'),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: Text(context.l10n.t('ui_cancel')),
      ),
      FilledButton(
        key: const Key('driverResetContinueButton'),
        onPressed: _loading ? null : (_codeSent ? _reset : _request),
        child: Text(
          context.l10n.t(
            _codeSent ? 'driver_reset_save' : 'driver_reset_send_code',
          ),
        ),
      ),
    ],
  );
}
