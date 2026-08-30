import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_token_refresher.dart';
import 'driver_token_storage.dart';

/// Shared driver auth HTTP stack: token storage + refresh + authenticated client.
class DriverSession {
  DriverSession._(
    this.tokenStorage, {
    ApiClient? apiClient,
    AuthTokenRefresher? tokenRefresher,
  }) {
    if (apiClient != null) {
      this.apiClient = apiClient;
      refresher =
          tokenRefresher ??
          AuthTokenRefresher(
            storage: tokenStorage,
            client: ApiClient(baseUrl: AppConfig.apiBaseUrl),
          );
      return;
    }

    final refreshClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    refresher = AuthTokenRefresher(
      storage: tokenStorage,
      client: refreshClient,
    );
    this.apiClient = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokenRefresher: refresher,
    );
  }

  factory DriverSession({
    DriverTokenStorage? tokenStorage,
    ApiClient? apiClient,
    AuthTokenRefresher? tokenRefresher,
  }) {
    final storage = tokenStorage ?? DriverTokenStorage();
    if (tokenStorage != null || apiClient != null || tokenRefresher != null) {
      return DriverSession._(
        storage,
        apiClient: apiClient,
        tokenRefresher: tokenRefresher,
      );
    }
    return _shared ??= DriverSession._(DriverTokenStorage());
  }

  static DriverSession? _shared;

  final DriverTokenStorage tokenStorage;
  late final AuthTokenRefresher refresher;
  late final ApiClient apiClient;

  static void resetSharedForTesting() {
    _shared = null;
  }

  Future<void> expireSession() async {
    final token = await tokenStorage.readAccessToken();
    await tokenStorage.clear();
    if (token == null || token.isEmpty) {
      return;
    }
    try {
      await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/logout'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best effort; local session cleanup already happened.
    }
  }
}
