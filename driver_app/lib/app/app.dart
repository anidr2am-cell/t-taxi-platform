import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/locale/locale_controller.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/account/data/account_api.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/bookings/data/booking_repository.dart';
import '../features/dispatch/data/dispatch_repository.dart';
import '../features/dispatch/data/driver_socket_service.dart';
import '../features/settlement/data/settlement_api.dart';
import '../core/firebase/fcm_token_service.dart';
import '../core/firebase/fcm_message_service.dart';
import '../l10n/app_localizations.dart';
import '../core/storage/secure_token_storage.dart';
import '../features/driver_application/data/driver_application_api.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({
    super.key,
    required this.config,
    required this.authController,
    required this.localeController,
    required this.bookingRepository,
    required this.dispatchRepository,
    this.accountApi,
    this.settlementApi,
    this.driverSocket,
    this.fcmTokenService,
    this.fcmMessageService,
    this.tokenStorage,
    this.driverApplicationApi,
  });

  final AppConfig config;
  final AuthController authController;
  final LocaleController localeController;
  final BookingReader bookingRepository;
  final DispatchReader dispatchRepository;
  final AccountDataSource? accountApi;
  final SettlementDataSource? settlementApi;
  final DriverSocketConnection? driverSocket;
  final FcmTokenService? fcmTokenService;
  final FcmMessageService? fcmMessageService;
  final TokenStorage? tokenStorage;
  final DriverApplicationDataSource? driverApplicationApi;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) {
        return MaterialApp(
          title: config.appName,
          locale: localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          debugShowCheckedModeBanner: config.environment.label != 'PROD',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A60)),
            useMaterial3: true,
          ),
          home: AuthGate(
            controller: authController,
            config: config,
            localeController: localeController,
            bookingRepository: bookingRepository,
            dispatchRepository: dispatchRepository,
            accountApi: accountApi,
            settlementApi: settlementApi,
            driverSocket: driverSocket,
            fcmTokenService: fcmTokenService,
            fcmMessageService: fcmMessageService,
            tokenStorage: tokenStorage,
            driverApplicationApi: driverApplicationApi,
          ),
        );
      },
    );
  }
}
