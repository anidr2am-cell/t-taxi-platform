import 'package:flutter/material.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../../driver_application/data/driver_application_api.dart';
import '../../driver_application/presentation/driver_application_form_page.dart';
import '../../driver_application/presentation/driver_application_status_page.dart';
import 'auth_controller.dart';
import 'language_selector.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.controller,
    required this.localeController,
    required this.appName,
    this.tokenStorage,
    this.driverApplicationApi,
  });

  final AuthController controller;
  final LocaleController localeController;
  final String appName;
  final TokenStorage? tokenStorage;
  final DriverApplicationDataSource? driverApplicationApi;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _hasSavedApplication = false;

  @override
  void initState() {
    super.initState();
    _loadSavedApplicationHint();
  }

  Future<void> _loadSavedApplicationHint() async {
    final storage = widget.tokenStorage;
    if (storage == null) return;
    final saved = await storage.readDriverApplicationInfo();
    if (!mounted) return;
    setState(() {
      _hasSavedApplication = saved != null &&
          saved.applicationNumber.isNotEmpty &&
          saved.statusToken.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.controller.login(
      _loginIdController.text.trim(),
      _passwordController.text,
    );
  }

  void _openSignUp() {
    final api = widget.driverApplicationApi;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DriverApplicationFormPage(
          api: api,
          tokenStorage: widget.tokenStorage,
        ),
      ),
    );
  }

  void _openApplicationStatus() {
    final api = widget.driverApplicationApi;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DriverApplicationStatusPage(
          api: api,
          tokenStorage: widget.tokenStorage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final submitting = widget.controller.status == AuthStatus.submitting;
    final errorMessage =
        widget.controller.lastError?.localizedMessage(l10n);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appName),
        actions: [
          LanguageSelector(
            controller: widget.localeController,
            compact: false,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.driverLogin,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('loginIdField'),
                    controller: _loginIdController,
                    enabled: !submitting,
                    autofillHints: const [
                      AutofillHints.telephoneNumber,
                      AutofillHints.username,
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.driverAccountLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? l10n.driverAccountRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('passwordField'),
                    controller: _passwordController,
                    enabled: !submitting,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: submitting ? null : (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        key: const Key('passwordVisibilityButton'),
                        tooltip: _obscurePassword
                            ? l10n.showPassword
                            : l10n.hidePassword,
                        onPressed: submitting
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? l10n.passwordRequired
                        : null,
                  ),
                  if (errorMessage case final message?) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      key: const Key('loginError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const Key('loginButton'),
                      onPressed: submitting ? null : _submit,
                      child: submitting
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.login),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    key: const Key('loginSignUpButton'),
                    onPressed:
                        submitting || widget.driverApplicationApi == null
                        ? null
                        : _openSignUp,
                    child: Text(l10n.loginSignUp),
                  ),
                  if (_hasSavedApplication)
                    FilledButton.tonal(
                      key: const Key('loginCheckApplicationStatusButton'),
                      onPressed:
                          submitting || widget.driverApplicationApi == null
                          ? null
                          : _openApplicationStatus,
                      child: Text(l10n.loginCheckApplicationStatus),
                    )
                  else
                    TextButton(
                      key: const Key('loginCheckApplicationStatusButton'),
                      onPressed:
                          submitting || widget.driverApplicationApi == null
                          ? null
                          : _openApplicationStatus,
                      child: Text(l10n.loginCheckApplicationStatus),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
