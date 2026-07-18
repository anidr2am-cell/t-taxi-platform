import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import 'auth_controller.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({
    super.key,
    required this.controller,
    required this.config,
  });

  final AuthController controller;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final user = controller.session!.user;
    final displayName = user.name?.trim().isNotEmpty == true
        ? user.name!
        : '기사 #${user.id}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('T-Ride 기사'),
        actions: [
          TextButton(
            key: const Key('logoutButton'),
            onPressed: controller.logout,
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64),
              const SizedBox(height: 16),
              Text('로그인 성공', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('환경: ${config.environment.label}'),
              Text(displayName),
            ],
          ),
        ),
      ),
    );
  }
}
