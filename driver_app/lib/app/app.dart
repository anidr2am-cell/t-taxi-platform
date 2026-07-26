import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/account/data/account_api.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/bookings/data/booking_repository.dart';
import '../features/dispatch/data/dispatch_repository.dart';
import '../features/dispatch/data/driver_socket_service.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({
    super.key,
    required this.config,
    required this.authController,
    required this.bookingRepository,
    required this.dispatchRepository,
    this.accountApi,
    this.driverSocket,
  });

  final AppConfig config;
  final AuthController authController;
  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final AccountDataSource? accountApi;
  final DriverSocketConnection? driverSocket;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: config.environment.label != 'PROD',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A60)),
        useMaterial3: true,
      ),
      home: AuthGate(
        controller: authController,
        config: config,
        bookingRepository: bookingRepository,
        dispatchRepository: dispatchRepository,
        accountApi: accountApi,
        driverSocket: driverSocket,
      ),
    );
  }
}
