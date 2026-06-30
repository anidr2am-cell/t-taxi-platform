import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/user_facing_error.dart';
import '../pages/driver_shell_page.dart';
import '../services/driver_api_service.dart';

class DriverLoginPage extends StatefulWidget {
  const DriverLoginPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverLoginPage> createState() => _DriverLoginPageState();
}

class _DriverLoginPageState extends State<DriverLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final DriverApiService _api;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DriverApiService();
    _openJobsIfLoggedIn();
  }

  Future<void> _openJobsIfLoggedIn() async {
    final token = await _api.getSavedToken();
    if (!mounted || token == null || token.isEmpty) return;
    _openHome();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => DriverShellPage(api: _api)),
    );
  }

  Future<void> _login() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) _openHome();
    } on DriverApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } catch (err) {
      if (mounted) setState(() => _error = userFacingError(err, fallback: context.l10n.t('ui_action_failed')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Text(
                'TTaxi Driver',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Log in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
