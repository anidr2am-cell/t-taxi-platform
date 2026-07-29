import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/app_environment.dart';
import '../core/firebase/firebase_app_initializer.dart';
import '../core/firebase/fcm_message_handler.dart';
import '../core/firebase/fcm_message_service.dart';
import '../core/firebase/fcm_token_service.dart';
import '../core/locale/locale_controller.dart';
import '../core/locale/locale_preferences.dart';
import '../core/network/api_client.dart';
import '../core/storage/secure_token_storage.dart';
import '../features/auth/data/auth_api.dart';
import '../features/account/data/account_api.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/bookings/data/booking_api.dart';
import '../features/bookings/data/booking_repository.dart';
import '../features/dispatch/data/dispatch_api.dart';
import '../features/dispatch/data/dispatch_repository.dart';
import '../features/dispatch/data/driver_socket_service.dart';
import '../features/settlement/data/settlement_api.dart';
import '../features/notifications/data/notification_api.dart';
import '../features/driver_application/data/driver_application_api.dart';
import 'app.dart';

Future<void> runDriverApp(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebaseApp();
  registerFcmBackgroundHandler();
  final config = AppConfig.forEnvironment(environment);
  final localePreferences = await LocalePreferences.create();
  final localeController = LocaleController(localePreferences);
  final apiClient = ApiClient(config: config, httpClient: http.Client());
  final storage = SecureTokenStorage();
  final notificationApi = NotificationApi(client: apiClient, storage: storage);
  final fcmTokenService = FcmTokenService(
    messaging: FirebaseFcmMessagingClient(),
    notificationApi: notificationApi,
    storage: storage,
  );
  final fcmMessageService = FcmMessageService(
    messaging: FirebaseFcmMessageStreams(),
  );
  final repository = AuthRepository(
    api: AuthApi(apiClient),
    storage: storage,
    fcmTokenService: fcmTokenService,
  );
  runApp(
    DriverApp(
      config: config,
      authController: AuthController(repository),
      localeController: localeController,
      bookingRepository: BookingRepository(
        BookingApi(client: apiClient, storage: storage),
      ),
      dispatchRepository: DispatchRepository(
        DispatchApi(client: apiClient, storage: storage),
      ),
      accountApi: AccountApi(client: apiClient, storage: storage),
      settlementApi: SettlementApi(client: apiClient, storage: storage),
      driverSocket: DriverSocketService(config: config, storage: storage),
      fcmTokenService: fcmTokenService,
      fcmMessageService: fcmMessageService,
      tokenStorage: storage,
      driverApplicationApi: DriverApplicationApi(client: apiClient),
    ),
  );
}
