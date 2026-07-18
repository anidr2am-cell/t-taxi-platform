import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/presentation/booking_list_screen.dart';
import 'auth_controller.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.config,
    required this.bookingRepository,
  });

  final AuthController controller;
  final AppConfig config;
  final BookingReader bookingRepository;

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
          AuthStatus.signedIn => BookingListScreen(
            repository: widget.bookingRepository,
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
