import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'auth_controller.dart';

Future<void> showPasswordResetDialog(
  BuildContext context, {
  required AuthController controller,
  String initialIdentifier = '',
}) => showDialog<void>(
  context: context,
  builder: (_) => _PasswordResetDialog(
    controller: controller,
    initialIdentifier: initialIdentifier,
  ),
);

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({
    required this.controller,
    required this.initialIdentifier,
  });
  final AuthController controller;
  final String initialIdentifier;
  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).resetPasswordFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request() async {
    final l10n = AppLocalizations.of(context);
    if (_identifier.text.trim().length < 5) {
      setState(() => _error = l10n.resetIdentifierRequired);
      return;
    }
    await _run(() async {
      await widget.controller.requestPasswordReset(_identifier.text.trim());
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = l10n.resetCodeInvalid);
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = l10n.resetPasswordMin);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.resetPasswordMismatch);
      return;
    }
    await _run(() async {
      await widget.controller.confirmPasswordReset(
        _identifier.text.trim(),
        _code.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.resetPasswordSuccess)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.resetPasswordTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_codeSent ? l10n.resetCodeHelp : l10n.resetRequestHelp),
            const SizedBox(height: 16),
            TextField(
              key: const Key('resetIdentifierField'),
              controller: _identifier,
              enabled: !_codeSent && !_loading,
              decoration: InputDecoration(labelText: l10n.resetIdentifier),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('resetCodeField'),
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(labelText: l10n.resetCode),
              ),
              TextField(
                key: const Key('resetPasswordField'),
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.newPassword),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('resetPasswordConfirmField'),
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.confirmNewPassword),
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
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('resetPasswordContinueButton'),
          onPressed: _loading ? null : (_codeSent ? _reset : _request),
          child: Text(_codeSent ? l10n.saveNewPassword : l10n.sendResetCode),
        ),
      ],
    );
  }
}
