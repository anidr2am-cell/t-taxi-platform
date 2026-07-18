import 'package:flutter/material.dart';

import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.controller,
    required this.appName,
  });

  final AuthController controller;
  final String appName;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

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

  @override
  Widget build(BuildContext context) {
    final submitting = widget.controller.status == AuthStatus.submitting;
    return Scaffold(
      appBar: AppBar(title: Text(widget.appName)),
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
                    '기사 로그인',
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
                    decoration: const InputDecoration(
                      labelText: '기사 계정 (전화번호 또는 이메일)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '기사 계정을 입력해 주세요.'
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
                      labelText: '비밀번호',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        key: const Key('passwordVisibilityButton'),
                        tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
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
                        ? '비밀번호를 입력해 주세요.'
                        : null,
                  ),
                  if (widget.controller.errorMessage case final message?) ...[
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
                          : const Text('로그인'),
                    ),
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
