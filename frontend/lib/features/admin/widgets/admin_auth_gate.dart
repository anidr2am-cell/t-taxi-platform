import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_dispatch/services/admin_dispatch_api_service.dart';

/// Ensures admin operational tabs have a saved JWT before rendering content.
class AdminAuthGate extends StatefulWidget {
  const AdminAuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<AdminAuthGate> {
  final _api = const AdminDispatchApiService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _checking = true;
  bool _loggedIn = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    final token = await _api.getSavedToken();
    setState(() {
      _loggedIn = token != null && token.isNotEmpty;
      _checking = false;
    });
  }

  Future<void> _login() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _submitting = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return AppUi.loadingState();
    }
    if (_loggedIn) {
      return widget.child;
    }
    return AppUi.centeredContent(
      child: Padding(
        padding: AppUi.pagePadding(context),
        child: AppUi.surfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Admin login required',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTokens.primaryDark,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                AppUi.surfaceCard(
                  backgroundColor: AppTokens.errorLight,
                  padding: const EdgeInsets.all(AppTokens.spaceSm),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.spaceMd),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _submitting ? null : _login,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
