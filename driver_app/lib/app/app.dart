import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/auth_gate.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({
    super.key,
    required this.config,
    required this.authController,
  });

  final AppConfig config;
  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: config.environment.label != 'PROD',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A60)),
        useMaterial3: true,
      ),
      home: AuthGate(controller: authController, config: config),
    );
  }
}
