import 'package:flutter/material.dart';

import '../services/driver_api_service.dart';
import 'driver_jobs_page.dart';

class DriverLoginPage extends StatefulWidget {
  const DriverLoginPage({super.key});

  @override
  State<DriverLoginPage> createState() => _DriverLoginPageState();
}

class _DriverLoginPageState extends State<DriverLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = DriverApiService();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _openJobsIfLoggedIn();
  }

  Future<void> _openJobsIfLoggedIn() async {
    final token = await _api.getSavedToken();
    if (!mounted || token == null || token.isEmpty) return;
    _openJobs();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openJobs() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverJobsPage()),
    );
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) _openJobs();
    } catch (err) {
      if (mounted) {
        setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
