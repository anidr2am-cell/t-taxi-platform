import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
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
    required this.localeController,
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
  final LocaleController localeController;
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
          AuthStatus.restoreError => _RestoreErrorBody(controller: widget.controller),
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
            localeController: widget.localeController,
            appName: widget.config.appName,
          ),
        };
      },
    );
  }
}

class _RestoreErrorBody extends StatelessWidget {
  const _RestoreErrorBody({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = controller.lastError?.localizedMessage(l10n) ??
        l10n.connectionFailed;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.initialize,
                child: Text(l10n.retry),
              ),
              TextButton(
                onPressed: controller.logout,
                child: Text(l10n.logoutFromThisDevice),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
