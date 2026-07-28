import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final user = controller.session!.user;
    final displayName = user.name?.trim().isNotEmpty == true
        ? user.name!
        : l10n.driverFallbackName(user.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tRideDriverTitle),
        actions: [
          TextButton(
            key: const Key('logoutButton'),
            onPressed: controller.logout,
            child: Text(l10n.logout),
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
              Text(
                l10n.loginSuccess,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(l10n.environmentLabel(config.environment.label)),
              Text(displayName),
            ],
          ),
        ),
      ),
    );
  }
}
