import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../account/data/account_api.dart';
import '../../bookings/data/booking_repository.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../../dispatch/data/driver_socket_service.dart';
import '../../settlement/data/settlement_api.dart';
import '../../../core/firebase/fcm_token_service.dart';
import '../../../core/firebase/fcm_message_service.dart';
import '../../dispatch/presentation/driver_home_shell.dart';
import 'auth_controller.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.config,
    required this.bookingRepository,
    required this.dispatchRepository,
    this.accountApi,
    this.settlementApi,
    this.driverSocket,
    this.fcmTokenService,
    this.fcmMessageService,
  });

  final AuthController controller;
  final AppConfig config;
  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final AccountDataSource? accountApi;
  final SettlementDataSource? settlementApi;
  final DriverSocketConnection? driverSocket;
  final FcmTokenService? fcmTokenService;
  final FcmMessageService? fcmMessageService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.status == AuthStatus.checking) {
      widget.controller.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return switch (widget.controller.status) {
          AuthStatus.checking => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          AuthStatus.restoreError => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.controller.errorMessage ?? '연결에 실패했습니다.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: widget.controller.initialize,
                      child: const Text('다시 시도'),
                    ),
                    TextButton(
                      onPressed: widget.controller.logout,
                      child: const Text('이 기기에서 로그아웃'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AuthStatus.signedIn => DriverHomeShell(
            bookingRepository: widget.bookingRepository,
            dispatchRepository: widget.dispatchRepository,
            accountApi: widget.accountApi,
            settlementApi: widget.settlementApi,
            driverSocket: widget.driverSocket,
            fcmTokenService: widget.fcmTokenService,
            fcmMessageService: widget.fcmMessageService,
            onUnauthorized: widget.controller.expireSession,
            onLogout: widget.controller.logout,
          ),
          AuthStatus.signedOut || AuthStatus.submitting => LoginScreen(
            controller: widget.controller,
            appName: widget.config.appName,
          ),
        };
      },
    );
  }
}
