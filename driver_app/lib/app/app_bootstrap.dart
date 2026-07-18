import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/app_environment.dart';
import '../core/network/api_client.dart';
import '../core/storage/secure_token_storage.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/bookings/data/booking_api.dart';
import '../features/bookings/data/booking_repository.dart';
import 'app.dart';

void runDriverApp(AppEnvironment environment) {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.forEnvironment(environment);
  final apiClient = ApiClient(config: config, httpClient: http.Client());
  final storage = SecureTokenStorage();
  final repository = AuthRepository(api: AuthApi(apiClient), storage: storage);
  runApp(
    DriverApp(
      config: config,
      authController: AuthController(repository),
      bookingRepository: BookingRepository(
        BookingApi(client: apiClient, storage: storage),
      ),
    ),
  );
}
