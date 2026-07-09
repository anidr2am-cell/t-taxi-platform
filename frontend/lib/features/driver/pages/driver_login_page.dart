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
  final _phoneController = TextEditingController();
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
    _phoneController.dispose();
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
        email: _phoneController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) _openHome();
    } on DriverApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } catch (err) {
      if (mounted) {
        setState(
          () => _error = userFacingError(
            err,
            fallback: context.l10n.t('ui_action_failed'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openApplicationForm() {
    Navigator.pushNamed(context, '/driver/apply');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('driver_login_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Text(
                context.l10n.t('driver_brand'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(
                  labelText: context.l10n.t('driver_phone'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: context.l10n.t('driver_password'),
                ),
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
                      : Text(context.l10n.t('driver_login')),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _openApplicationForm,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(context.l10n.t('driver_application_cta')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
